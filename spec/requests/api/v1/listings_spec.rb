require "swagger_helper"

RSpec.describe "Api::V1::ListingsController", type: :request do
  path "/api/v1/listings" do
    get "browse active listings" do
      tags "Listings"
      description "Returns paginated active listings for buyers"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :search,         in: :query,  type: :string,  required: false
      parameter name: :category_id,    in: :query,  type: :integer, required: false
      parameter name: :sort,           in: :query,  type: :string,  required: false,
                description: "Sort order. Allowed values: newest (default), oldest, price_asc, price_desc. Unknown values fall back to newest."

      let(:user)  { create(:user) }
      let(:headers) { auth_headers_for(user) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid)    { headers["uid"] }

      response "200", "guest can browse without auth" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid)    { nil }
        before { create_list(:listing, 2, :active) }

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)["listings"]).to be_an(Array)
        end
      end

      response "200", "successful" do
        before { create_list(:listing, 3, :active) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listings"]).to be_an(Array)
          expect(data["meta"]["pagination"]).to have_key("total_count")
          expect(data["listings"].first).to have_key("image_urls")
          expect(data["listings"].first["image_urls"]).to be_an(Array)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "sort=newest returns listings ordered by created_at desc" do
        let(:sort) { "newest" }

        before do
          create(:listing, :active, created_at: 3.days.ago)
          create(:listing, :active, created_at: 1.day.ago)
          create(:listing, :active, created_at: 1.hour.ago)
        end

        run_test! do |response|
          created_ats = JSON.parse(response.body)["listings"].map { |l| l["created_at"] }
          expect(created_ats).to eq(created_ats.sort.reverse)
        end
      end

      response "200", "sort=oldest returns listings ordered by created_at asc" do
        let(:sort) { "oldest" }

        before do
          create(:listing, :active, created_at: 3.days.ago)
          create(:listing, :active, created_at: 1.day.ago)
          create(:listing, :active, created_at: 1.hour.ago)
        end

        run_test! do |response|
          created_ats = JSON.parse(response.body)["listings"].map { |l| l["created_at"] }
          expect(created_ats).to eq(created_ats.sort)
        end
      end

      response "200", "sort=price_asc returns listings ordered by ascending price" do
        let(:sort) { "price_asc" }

        before do
          create(:listing, :active, price: 500)
          create(:listing, :active, price: 100)
          create(:listing, :active, price: 300)
        end

        run_test! do |response|
          prices = JSON.parse(response.body)["listings"].map { |l| l["price"].to_f }
          expect(prices).to eq(prices.sort)
        end
      end

      response "200", "sort=price_desc returns listings ordered by descending price" do
        let(:sort) { "price_desc" }

        before do
          create(:listing, :active, price: 500)
          create(:listing, :active, price: 100)
          create(:listing, :active, price: 300)
        end

        run_test! do |response|
          prices = JSON.parse(response.body)["listings"].map { |l| l["price"].to_f }
          expect(prices).to eq(prices.sort.reverse)
        end
      end

      response "200", "absent or invalid sort falls back to newest (created_at desc)" do
        let(:sort) { "invalid_sort_key" }

        before do
          create(:listing, :active)
          create(:listing, :active)
          create(:listing, :active)
        end

        run_test! do |response|
          listings = JSON.parse(response.body)["listings"]
          created_ats = listings.map { |l| l["created_at"] }
          expect(created_ats).to eq(created_ats.sort.reverse)
        end
      end
    end
  end

  path "/api/v1/listings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "get a listing" do
      tags "Listings"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:user)    { create(:user) }
      let(:headers) { auth_headers_for(user) }
      let(:"access-token") { headers["access-token"] }
      let(:client)  { headers["client"] }
      let(:uid)     { headers["uid"] }
      let(:listing) { create(:listing, :active) }
      let(:id)      { listing.id }

      response "404", "not found" do
        let(:id) { 0 }
        run_test! do |response|
          expect(response).to have_http_status(:not_found)
        end
      end

      response "200", "successful — authenticated non-owner sees seller phone" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["id"]).to eq(listing.id)
          expect(data["listing"]).to have_key("description")
          expect(data["listing"]).to have_key("images")
          expect(data["listing"]).to have_key("seller")
          expect(data["listing"]).to have_key("category")
          # Authenticated user who does NOT own the listing must see the phone
          expect(data["listing"]["seller"]["phone"]).to eq(listing.user.phone)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "guest (no auth) does NOT see seller phone" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid)    { nil }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["seller"]["phone"]).to be_nil
        end
      end

      response "200", "listing owner viewing their own listing does NOT see phone in seller hash" do
        # The authenticated user IS the listing owner — phone should also be nil
        let(:listing) { create(:listing, :active, user: user) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["seller"]["phone"]).to be_nil
        end
      end
    end
  end

  path "/api/v1/listings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "is_saved reflects whether the current user has saved the listing" do
      tags "Listings"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:user)    { create(:user) }
      let(:headers) { auth_headers_for(user) }
      let(:"access-token") { headers["access-token"] }
      let(:client)  { headers["client"] }
      let(:uid)     { headers["uid"] }
      let(:listing) { create(:listing, :active) }
      let(:id)      { listing.id }

      response "200", "is_saved is false when listing not saved" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["is_saved"]).to eq(false)
        end
      end

      response "200", "is_saved is true when listing is saved by current user" do
        before { create(:saved_listing, user: user, listing: listing) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["is_saved"]).to eq(true)
        end
      end
    end
  end
end
