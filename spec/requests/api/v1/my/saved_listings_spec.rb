require "rails_helper"

RSpec.describe "Api::V1::My::SavedListings", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/my/saved_listings" do
    it "requires authentication" do
      get "/api/v1/my/saved_listings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with the saved listings under the listings key" do
      saved_a = create(:listing, :active)
      saved_b = create(:listing, :active)
      create(:saved_listing, user: user, listing: saved_a)
      create(:saved_listing, user: user, listing: saved_b)
      create(:saved_listing) # another user's save — must not appear

      get "/api/v1/my/saved_listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("listings")
      ids = body["listings"].map { |l| l["id"] }
      expect(ids).to contain_exactly(saved_a.id, saved_b.id)
    end

    it "returns an empty listings array when nothing is saved" do
      get "/api/v1/my/saved_listings", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body["listings"]).to eq([])
    end

    it "includes pagination meta in the response" do
      get "/api/v1/my/saved_listings", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body).to have_key("meta")
      expect(body["meta"]).to have_key("pagination")
      pagination = body["meta"]["pagination"]
      expect(pagination).to have_key("current_page")
      expect(pagination).to have_key("total_count")
      expect(pagination).to have_key("total_pages")
      expect(pagination).to have_key("next_page")
      expect(pagination).to have_key("prev_page")
    end

    context "pagination" do
      # Pagy default page size is 20; create 30 saved listings so page 2 exists.
      before do
        category = create(:category)
        30.times do
          listing = create(:listing, :active, category: category)
          create(:saved_listing, user: user, listing: listing)
        end
      end

      it "page 1 returns the default page size and meta.pagination is present" do
        get "/api/v1/my/saved_listings?page[number]=1", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listings"].length).to eq(20)
        pagination = body.dig("meta", "pagination")
        expect(pagination["current_page"]).to eq(1)
        expect(pagination["total_count"]).to eq(30)
        expect(pagination["total_pages"]).to eq(2)
        expect(pagination["next_page"]).to eq(2)
        expect(pagination["prev_page"]).to be_nil
      end

      it "page 2 returns the remainder" do
        get "/api/v1/my/saved_listings?page[number]=2", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listings"].length).to eq(10)
        pagination = body.dig("meta", "pagination")
        expect(pagination["current_page"]).to eq(2)
        expect(pagination["next_page"]).to be_nil
        expect(pagination["prev_page"]).to eq(1)
      end

      it "page 1 ids and page 2 ids are disjoint (no duplicates across pages)" do
        get "/api/v1/my/saved_listings?page[number]=1", headers: headers, as: :json
        page1_ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }

        get "/api/v1/my/saved_listings?page[number]=2", headers: headers, as: :json
        page2_ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }

        expect(page1_ids & page2_ids).to be_empty
      end
    end

    it "filter_maps out a saved record whose listing has been deleted (soft-removed)" do
      active_listing  = create(:listing, :active)
      deleted_listing = create(:listing, :active)

      create(:saved_listing, user: user, listing: active_listing)
      create(:saved_listing, user: user, listing: deleted_listing)

      # Simulate a hard-deleted listing: destroy the record without touching SavedListing
      deleted_listing.destroy!

      # The orphaned saved record's foreign key points to nothing.
      # The controller's filter_map(&:listing) must silently drop it.
      expect { get "/api/v1/my/saved_listings", headers: headers, as: :json }
        .not_to raise_error

      body = JSON.parse(response.body)
      # Only the still-active listing should appear
      ids = body["listings"].map { |l| l["id"] }
      expect(ids).to eq([ active_listing.id ])
      expect(ids).not_to include(deleted_listing.id)
    end

    it "executes a constant number of queries regardless of saved-listing count (no N+1)" do
      category = create(:category)

      # Warm up: make one request first so Rails connection-pool and auth
      # token caches are populated. Without a warm-up the first timed request
      # picks up extra schema/session queries that skew the baseline.
      get "/api/v1/my/saved_listings", headers: headers, as: :json

      # Baseline: 1 saved listing. Each listing gets its OWN seller (no shared
      # user) so the seller-avatar lookup (u.avatar.attached?/.url in the :list
      # view) would be O(N) without eager-loading user.avatar_attachment — i.e.
      # this test actually exercises the avatar N+1, not just listing rows.
      listing_1 = create(:listing, :active, category: category)
      create(:saved_listing, user: user, listing: listing_1)

      queries_with_1 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_1 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/my/saved_listings", headers: headers, as: :json
      end

      # Scale up: 3 total saved listings, each with a DISTINCT seller.
      listing_2 = create(:listing, :active, category: category)
      listing_3 = create(:listing, :active, category: category)
      create(:saved_listing, user: user, listing: listing_2)
      create(:saved_listing, user: user, listing: listing_3)

      queries_with_3 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_3 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/my/saved_listings", headers: headers, as: :json
      end

      # With eager-loading the count must be constant. We allow up to 3 extra
      # queries for minor per-request overhead (token refresh, schema cache
      # warming) but must not grow O(N) with the number of saved listings.
      expect(queries_with_3).to be <= queries_with_1 + 3,
        "Expected query count to be constant (no N+1), " \
        "but got #{queries_with_1} queries with 1 listing and #{queries_with_3} with 3 listings"
    end

    it "does not issue N+1 queries for price_histories when listings have price drops" do
      category = create(:category)

      # Warm up
      get "/api/v1/my/saved_listings", headers: headers, as: :json

      # 1 saved listing with a recent price drop
      listing_1 = create(:listing, :active, category: category)
      create(:listing_price_history, :recent_drop, listing: listing_1)
      create(:saved_listing, user: user, listing: listing_1)

      queries_with_1 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_1 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/my/saved_listings", headers: headers, as: :json
      end

      # 3 saved listings all with recent price drops
      listing_2 = create(:listing, :active, category: category)
      listing_3 = create(:listing, :active, category: category)
      create(:listing_price_history, :recent_drop, listing: listing_2)
      create(:listing_price_history, :recent_drop, listing: listing_3)
      create(:saved_listing, user: user, listing: listing_2)
      create(:saved_listing, user: user, listing: listing_3)

      queries_with_3 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_3 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/my/saved_listings", headers: headers, as: :json
      end

      # Without :price_histories in includes the query count grows O(N);
      # with it the count must remain constant (within small fixed overhead).
      expect(queries_with_3).to be <= queries_with_1 + 3,
        "price_histories N+1 regression: got #{queries_with_1} queries with 1 listing " \
        "and #{queries_with_3} with 3 listings (price_histories not eager-loaded?)"
    end

    it "returns price_drop_percent for a saved listing that has a recent price drop" do
      listing = create(:listing, :active)
      create(:listing_price_history, :recent_drop, listing: listing)
      create(:saved_listing, user: user, listing: listing)

      get "/api/v1/my/saved_listings", headers: headers, as: :json

      body = JSON.parse(response.body)
      item = body["listings"].find { |l| l["id"] == listing.id }
      expect(item).not_to be_nil
      expect(item["price_drop_percent"]).to be_an(Integer)
      expect(item["price_drop_percent"]).to be > 0
    end
  end
end
