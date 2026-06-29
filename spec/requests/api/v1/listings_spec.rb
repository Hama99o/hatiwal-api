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
      parameter name: :sort,                in: :query,  type: :string,  required: false,
                description: "Sort order. Allowed values: newest (default), oldest, price_asc, price_desc, most_viewed, nearest. " \
                             "nearest requires latitude/longitude and falls back to newest when they are absent. Unknown values fall back to newest."
      parameter name: :latitude,  in: :query, type: :number, required: false,
                description: "Buyer's latitude. Used for radius filtering and for sort=nearest."
      parameter name: :longitude, in: :query, type: :number, required: false,
                description: "Buyer's longitude. Used for radius filtering and for sort=nearest."
      parameter name: :radius,    in: :query, type: :number, required: false,
                description: "Radius in kilometers — requires latitude and longitude."
      parameter name: :seller_active_days, in: :query,  type: :integer, required: false,
                description: "When present, restricts results to listings whose seller's last_sign_in_at is within this many days. E.g. 7 returns listings from sellers active in the last week."

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

      response "200", "sort=most_viewed returns listings ordered by views_count descending" do
        let(:sort) { "most_viewed" }

        let!(:low_views)    { create(:listing, :active, views_count: 0) }
        let!(:medium_views) { create(:listing, :active, views_count: 5) }
        let!(:high_views)   { create(:listing, :active, views_count: 10) }

        run_test! do |response|
          views = JSON.parse(response.body)["listings"].map { |l| l["views_count"] }
          expect(views).to eq([ 10, 5, 0 ])
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "sort=nearest orders by distance when coordinates are present" do
        let(:sort)      { "nearest" }
        let(:latitude)  { 34.5553 }
        let(:longitude) { 69.2075 }

        let!(:near) { create(:listing, :active, latitude: 34.5800, longitude: 69.2100) }
        let!(:far)  { create(:listing, :active, latitude: 34.3529, longitude: 62.2040) }

        run_test! do |response|
          ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
          expect(ids).to eq([ near.id, far.id ])
        end
      end

      response "200", "sort=nearest falls back to newest when coordinates are absent" do
        let(:sort) { "nearest" }

        before do
          create(:listing, :active, created_at: 3.days.ago)
          create(:listing, :active, created_at: 1.hour.ago)
        end

        run_test! do |response|
          created_ats = JSON.parse(response.body)["listings"].map { |l| l["created_at"] }
          expect(created_ats).to eq(created_ats.sort.reverse)
        end
      end

      response "200", "sort=most_viewed composes with search filter (guest)" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        let(:sort)           { "most_viewed" }
        let(:search)         { "red bicycle" }

        before do
          create(:listing, :active, title: "red bicycle", views_count: 2)
          create(:listing, :active, title: "red bicycle", views_count: 8)
          create(:listing, :active, title: "blue shoes",  views_count: 99)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          # Only the two "red bicycle" listings, ordered by views_count desc
          listings = JSON.parse(response.body)["listings"]
          expect(listings.length).to eq(2)
          views = listings.map { |l| l["views_count"] }
          expect(views).to eq([ 8, 2 ])
        end
      end

      response "200", "seller_active_days=7 includes listings from recently-active sellers and excludes stale ones" do
        let(:seller_active_days) { 7 }

        let!(:recent_seller)  { create(:user).tap { |u| u.update_column(:last_sign_in_at, 2.days.ago) } }
        let!(:stale_seller)   { create(:user).tap { |u| u.update_column(:last_sign_in_at, 30.days.ago) } }
        let!(:recent_listing) { create(:listing, :active, user: recent_seller) }
        let!(:stale_listing)  { create(:listing, :active, user: stale_seller) }

        run_test! do |response|
          ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
          expect(ids).to     include(recent_listing.id)
          expect(ids).not_to include(stale_listing.id)
        end
      end

      response "200", "seller_active_days absent — all active listings returned regardless of seller activity" do
        let!(:stale_seller)  { create(:user).tap { |u| u.update_column(:last_sign_in_at, 60.days.ago) } }
        let!(:stale_listing) { create(:listing, :active, user: stale_seller) }

        run_test! do |response|
          ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
          expect(ids).to include(stale_listing.id)
        end
      end

      response "200", "seller_active_days composes with search filter (guest)" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        let(:seller_active_days) { 7 }

        let!(:active_seller)   { create(:user).tap { |u| u.update_column(:last_sign_in_at, 1.day.ago) } }
        let!(:inactive_seller) { create(:user).tap { |u| u.update_column(:last_sign_in_at, 30.days.ago) } }

        before do
          create(:listing, :active, title: "blue bicycle", user: active_seller)
          create(:listing, :active, title: "blue bicycle", user: inactive_seller)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          listings = JSON.parse(response.body)["listings"]
          # Only the listing from the active seller should appear
          expect(listings.length).to eq(1)
          expect(listings.first["seller"]["id"]).to eq(active_seller.id)
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

    get "views_count — owner view never increments" do
      tags "Listings"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:owner)   { create(:user) }
      let(:headers) { auth_headers_for(owner) }
      let(:"access-token") { headers["access-token"] }
      let(:client)  { headers["client"] }
      let(:uid)     { headers["uid"] }
      let(:listing) { create(:listing, :active, user: owner, views_count: 0) }
      let(:id)      { listing.id }

      response "200", "owner GET leaves views_count unchanged" do
        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(listing.reload.views_count).to eq(0)
        end
      end
    end
  end

  path "/api/v1/listings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "views_count — non-owner first GET increments, second GET does not" do
      tags "Listings"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:viewer)  { create(:user) }
      let(:headers) { auth_headers_for(viewer) }
      let(:"access-token") { headers["access-token"] }
      let(:client)  { headers["client"] }
      let(:uid)     { headers["uid"] }
      let(:listing) { create(:listing, :active, views_count: 0) }
      let(:id)      { listing.id }

      response "200", "first GET by non-owner increments views_count to 1" do
        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(listing.reload.views_count).to eq(1)
        end
      end

      response "200", "second GET by same non-owner does not increment views_count" do
        before do
          ListingView.record!(viewer, listing)
          listing.update_column(:views_count, 1)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(listing.reload.views_count).to eq(1)
        end
      end
    end
  end

  path "/api/v1/listings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "views_count — guest GET increments" do
      tags "Listings"
      produces "application/json"

      let(:listing) { create(:listing, :active, views_count: 0) }
      let(:id)      { listing.id }

      response "200", "guest GET increments views_count" do
        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(listing.reload.views_count).to eq(1)
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

  path "/api/v1/listings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "saves_count reflects the number of SavedListing records (saved-by-N social proof)" do
      tags "Listings"
      produces "application/json"

      let(:listing) { create(:listing, :active) }
      let(:id)      { listing.id }

      response "200", "saves_count is 0 when nobody has saved the listing" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["saves_count"]).to eq(0)
        end
      end

      response "200", "saves_count matches the exact SavedListing count" do
        before { create_list(:saved_listing, 4, listing: listing) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["saves_count"]).to eq(4)
          expect(data["listing"]["saves_count"]).to eq(SavedListing.where(listing: listing).count)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "saves_count is visible to a guest (no auth headers)" do
        before { create_list(:saved_listing, 2, listing: listing) }

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["listing"]["saves_count"]).to eq(2)
        end
      end

      response "200", "saves_count is an integer, never a nested list of savers" do
        before { create(:saved_listing, listing: listing) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listing"]["saves_count"]).to be_a(Integer)
          expect(data["listing"].keys).not_to include("savers", "saved_by_users")
        end
      end
    end
  end

  path "/api/v1/listings/{id}/save" do
    parameter name: :id, in: :path, type: :integer

    post "save a listing (bookmark)" do
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

      response "200", "saves a listing and returns saved:true with the SavedListing id" do
        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["saved"]).to eq(true)
          expect(data["id"]).to be_a(Integer)
          expect(SavedListing.exists?(user: user, listing: listing)).to eq(true)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "save is idempotent — saving twice still returns 200 and persists one record" do
        before { create(:saved_listing, user: user, listing: listing) }

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["saved"]).to eq(true)
          expect(SavedListing.where(user: user, listing: listing).count).to eq(1)
        end
      end

      response "401", "unauthenticated user cannot save" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid)    { nil }

        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end

  path "/api/v1/listings/{id}/unsave" do
    parameter name: :id, in: :path, type: :integer

    delete "unsave a listing (remove bookmark)" do
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

      response "200", "unsaves a listing and returns saved:false" do
        before { create(:saved_listing, user: user, listing: listing) }

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["saved"]).to eq(false)
          expect(SavedListing.exists?(user: user, listing: listing)).to eq(false)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "unsave is idempotent — calling when not saved still returns 200" do
        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["saved"]).to eq(false)
        end
      end

      response "401", "unauthenticated user cannot unsave" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid)    { nil }

        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end

  path "/api/v1/listings/{id}/similar" do
    parameter name: :id, in: :path, type: :integer

    get "similar listings rail" do
      tags "Listings"
      description "Returns up to 8 browsable listings in the same category, excluding the source listing. Public — guests and authenticated users both have access."
      produces "application/json"

      let(:category)  { create(:category) }
      let(:source)    { create(:listing, :active, category: category) }
      let(:id)        { source.id }

      response "200", "returns same-category browsable listings excluding the source" do
        before do
          create_list(:listing, 3, :active, category: category)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listings"]).to be_an(Array)
          expect(data["listings"].length).to eq(3)
          expect(data["listings"].map { |l| l["id"] }).not_to include(source.id)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "excludes the source listing from results" do
        before do
          create(:listing, :active, category: category)
        end

        run_test! do |response|
          ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
          expect(ids).not_to include(source.id)
        end
      end

      response "200", "excludes draft and sold listings" do
        before do
          create(:listing, :active, category: category)
          create(:listing, status: :draft, category: category)
          create(:listing, :sold, category: category)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          # Only the active listing — draft and sold are never browsable
          expect(data["listings"].length).to eq(1)
          expect(data["listings"].first["status"]).to eq("active")
        end
      end

      response "200", "works for a guest (no auth headers)" do
        before do
          create_list(:listing, 2, :active, category: category)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)["listings"]).to be_an(Array)
        end
      end

      response "404", "not found for non-existent listing" do
        let(:id) { 0 }

        run_test! do |response|
          expect(response).to have_http_status(:not_found)
        end
      end

      response "200", "capped at 8 — creating 9 same-category active listings returns exactly 8" do
        before do
          create_list(:listing, 9, :active, category: category)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["listings"].length).to eq(8)
        end
      end
    end
  end
end
