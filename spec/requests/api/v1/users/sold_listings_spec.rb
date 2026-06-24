require "swagger_helper"

RSpec.describe "Api::V1::Users::SoldListingsController", type: :request do
  let(:seller)    { create(:user, firstname: "Ahmad", lastname: "Shah") }
  let(:requester) { create(:user) }

  # ── RSwag path ────────────────────────────────────────────────────────────────
  path "/api/v1/users/{user_id}/sold_listings" do
    get "list a seller's sold listings (public)" do
      tags "Users"
      description <<~DESC
        Returns a paginated list of sold listings for any publicly-active seller.
        Works for guests — authentication is optional. Returns 404 when the
        seller account has been deleted or is pending deletion.
      DESC
      produces "application/json"

      parameter name: :user_id, in: :path, type: :integer, required: true,
                description: "Seller's user ID"
      parameter name: :"page[number]", in: :query, type: :integer, required: false,
                description: "Page number (default: 1)"

      let(:user_id) { seller.id }

      response "200", "returns only sold listings (guest)" do
        before do
          create(:listing, :sold, user: seller)
          create(:listing, :active, user: seller)   # must be excluded
          create(:listing, :draft, user: seller)    # must be excluded
          create(:listing, :reserved, user: seller) # must be excluded
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["listings"]).to be_an(Array)
          expect(data["listings"].length).to eq(1)
          expect(data["listings"].first["status"]).to eq("sold")
          expect(data["meta"]["pagination"]).to have_key("total_count")
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "returns only that seller's sold listings (authenticated)" do
        let(:headers) { auth_headers_for(requester) }
        let(:"access-token") { headers["access-token"] }
        let(:client)         { headers["client"] }
        let(:uid)            { headers["uid"] }

        parameter name: :"access-token", in: :header, type: :string, required: false
        parameter name: :client,         in: :header, type: :string, required: false
        parameter name: :uid,            in: :header, type: :string, required: false

        before do
          create(:listing, :sold, user: seller)
          create(:listing, :sold, user: seller)
          other_seller = create(:user)
          create(:listing, :sold, user: other_seller) # another seller — must NOT appear
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["listings"].length).to eq(2)
          data["listings"].each do |l|
            expect(l["status"]).to eq("sold")
          end
        end
      end

      response "404", "seller not found" do
        let(:user_id) { 0 }

        run_test! do |response|
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  # ── Functional specs ─────────────────────────────────────────────────────────

  describe "GET /api/v1/users/:user_id/sold_listings" do
    context "as a guest (no auth token)" do
      it "returns 200 and only sold listings" do
        create(:listing, :sold,     user: seller)
        create(:listing, :active,   user: seller)   # excluded
        create(:listing, :draft,    user: seller)   # excluded
        create(:listing, :reserved, user: seller)   # excluded

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        expect(response).to have_http_status(:ok)
        listings = JSON.parse(response.body)["listings"]
        expect(listings.length).to eq(1)
        expect(listings.first["status"]).to eq("sold")
      end

      it "excludes sold listings that belong to a different seller" do
        create(:listing, :sold, user: seller)
        other_seller = create(:user)
        create(:listing, :sold, user: other_seller)

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        listings = JSON.parse(response.body)["listings"]
        expect(listings.length).to eq(1)
      end

      it "returns 404 for a deleted user (deletion_scheduled_at set)" do
        seller.update!(deletion_scheduled_at: 1.day.ago)

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for a non-existent user" do
        get "/api/v1/users/0/sold_listings", as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "returns an empty listings array when the seller has no sold items" do
        create(:listing, :active, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        expect(response).to have_http_status(:ok)
        listings = JSON.parse(response.body)["listings"]
        expect(listings).to be_empty
      end

      it "returns pagination metadata" do
        create_list(:listing, 3, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings?page[number]=1", as: :json

        data = JSON.parse(response.body)
        expect(data["meta"]["pagination"]["total_count"]).to eq(3)
        expect(data["meta"]["pagination"]["total_pages"]).to eq(1)
        expect(data["meta"]["pagination"]["current_page"]).to eq(1)
        expect(data["listings"].length).to eq(3)
      end

      it "returns the :list serializer fields (thumbnail_url, seller, category)" do
        create(:listing, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        l = JSON.parse(response.body)["listings"].first
        expect(l).to have_key("thumbnail_url")
        expect(l).to have_key("seller")
        expect(l).to have_key("category")
        expect(l["seller"]["id"]).to eq(seller.id)
      end
    end

    context "as an authenticated user" do
      let(:headers) { auth_headers_for(requester) }

      it "returns 200 and only sold listings for the requested seller" do
        create(:listing, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listings"].length).to eq(1)
      end

      it "does not expose a deleted seller's listings" do
        seller.update!(deletion_scheduled_at: 1.hour.ago)
        create(:listing, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context "admin-removed sold listings" do
      it "excludes a sold listing that has been taken down by an admin (removed_at set)" do
        create(:listing, :sold, user: seller, removed_at: Time.current)
        create(:listing, :sold, user: seller) # not removed — must appear

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        expect(response).to have_http_status(:ok)
        listings = JSON.parse(response.body)["listings"]
        expect(listings.length).to eq(1)
        listings.each { |l| expect(l["removed_at"]).to be_nil }
      end

      it "returns an empty array when all of the seller's sold listings have been removed" do
        create(:listing, :sold, user: seller, removed_at: Time.current)

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listings"]).to be_empty
      end
    end

    context "block relationships" do
      it "returns sold listings to a guest regardless of any blocks (guests cannot block)" do
        create(:listing, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings", as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listings"].length).to eq(1)
      end

      it "hides sold listings from a viewer who has blocked the seller" do
        create(:block, blocker: requester, blocked: seller)
        create(:listing, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings",
            headers: auth_headers_for(requester), as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listings"]).to be_empty
      end

      it "hides sold listings from a viewer who has been blocked by the seller" do
        create(:block, blocker: seller, blocked: requester)
        create(:listing, :sold, user: seller)

        get "/api/v1/users/#{seller.id}/sold_listings",
            headers: auth_headers_for(requester), as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listings"]).to be_empty
      end

      it "still shows sold listings to an unrelated authenticated user" do
        create(:listing, :sold, user: seller)
        unrelated = create(:user)

        get "/api/v1/users/#{seller.id}/sold_listings",
            headers: auth_headers_for(unrelated), as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listings"].length).to eq(1)
      end
    end
  end
end
