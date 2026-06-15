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

    it "does not include pagination meta in the response" do
      get "/api/v1/my/saved_listings", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body.keys).to contain_exactly("listings")
    end

    it "controller source contains no render json: literal" do
      controller_path = Rails.root.join(
        "app/controllers/api/v1/my/saved_listings_controller.rb"
      )
      source = File.read(controller_path)
      expect(source).not_to include("render json:")
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
