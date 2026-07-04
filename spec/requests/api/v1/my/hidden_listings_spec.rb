require "rails_helper"

RSpec.describe "Api::V1::My::HiddenListings", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/my/hidden_listings" do
    it "requires authentication" do
      get "/api/v1/my/hidden_listings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with the hidden listings under the listings key" do
      hidden_a = create(:listing, :active)
      hidden_b = create(:listing, :active)
      create(:hidden_listing, user: user, listing: hidden_a)
      create(:hidden_listing, user: user, listing: hidden_b)
      create(:hidden_listing) # another user's hide — must not appear

      get "/api/v1/my/hidden_listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("listings")
      ids = body["listings"].map { |l| l["id"] }
      expect(ids).to contain_exactly(hidden_a.id, hidden_b.id)
    end

    it "returns an empty listings array when nothing is hidden" do
      get "/api/v1/my/hidden_listings", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body["listings"]).to eq([])
    end

    it "includes pagination meta in the response" do
      get "/api/v1/my/hidden_listings", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body).to have_key("meta")
      expect(body["meta"]).to have_key("pagination")
      pagination = body["meta"]["pagination"]
      expect(pagination).to have_key("current_page")
      expect(pagination).to have_key("total_count")
      expect(pagination).to have_key("total_pages")
    end

    context "pagination" do
      before do
        category = create(:category)
        30.times do
          listing = create(:listing, :active, category: category)
          create(:hidden_listing, user: user, listing: listing)
        end
      end

      it "page 1 returns the default page size" do
        get "/api/v1/my/hidden_listings?page[number]=1", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listings"].length).to eq(20)
        pagination = body.dig("meta", "pagination")
        expect(pagination["current_page"]).to eq(1)
        expect(pagination["total_count"]).to eq(30)
        expect(pagination["total_pages"]).to eq(2)
      end

      it "page 2 returns the remainder" do
        get "/api/v1/my/hidden_listings?page[number]=2", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listings"].length).to eq(10)
      end
    end

    it "filter_maps out a hidden record whose listing has been deleted" do
      active_listing  = create(:listing, :active)
      deleted_listing = create(:listing, :active)

      create(:hidden_listing, user: user, listing: active_listing)
      create(:hidden_listing, user: user, listing: deleted_listing)

      deleted_listing.destroy!

      expect { get "/api/v1/my/hidden_listings", headers: headers, as: :json }
        .not_to raise_error

      body = JSON.parse(response.body)
      ids = body["listings"].map { |l| l["id"] }
      expect(ids).to eq([ active_listing.id ])
      expect(ids).not_to include(deleted_listing.id)
    end

    it "executes a constant number of queries regardless of hidden-listing count (no N+1)" do
      category = create(:category)

      get "/api/v1/my/hidden_listings", headers: headers, as: :json

      listing_1 = create(:listing, :active, category: category)
      create(:hidden_listing, user: user, listing: listing_1)

      queries_with_1 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_1 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/my/hidden_listings", headers: headers, as: :json
      end

      listing_2 = create(:listing, :active, category: category)
      listing_3 = create(:listing, :active, category: category)
      create(:hidden_listing, user: user, listing: listing_2)
      create(:hidden_listing, user: user, listing: listing_3)

      queries_with_3 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_3 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/my/hidden_listings", headers: headers, as: :json
      end

      expect(queries_with_3).to be <= queries_with_1 + 3,
        "Expected query count to be constant (no N+1), " \
        "but got #{queries_with_1} queries with 1 listing and #{queries_with_3} with 3 listings"
    end
  end
end
