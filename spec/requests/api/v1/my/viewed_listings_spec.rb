require "rails_helper"

RSpec.describe "Api::V1::My::ViewedListings", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/my/viewed_listings" do
    # ── Authentication ────────────────────────────────────────────────────────

    it "returns 401 for a guest (no auth headers)" do
      get "/api/v1/my/viewed_listings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # ── Happy path ────────────────────────────────────────────────────────────

    it "returns 200 with the viewed listings under the listings key" do
      listing_a = create(:listing, :active)
      listing_b = create(:listing, :active)

      create(:listing_view, user: user, listing: listing_a, last_viewed_at: 2.hours.ago)
      create(:listing_view, user: user, listing: listing_b, last_viewed_at: 1.hour.ago)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("listings")
      ids = body["listings"].map { |l| l["id"] }
      expect(ids).to contain_exactly(listing_a.id, listing_b.id)
    end

    it "returns an empty listings array when nothing has been viewed" do
      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["listings"]).to eq([])
    end

    it "does NOT include another user's view history" do
      other_user    = create(:user)
      other_listing = create(:listing, :active)
      create(:listing_view, user: other_user, listing: other_listing)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      body = JSON.parse(response.body)
      ids  = body["listings"].map { |l| l["id"] }
      expect(ids).not_to include(other_listing.id)
    end

    # ── Browsable-only guard ──────────────────────────────────────────────────

    it "excludes draft listings from the response" do
      browsable_listing = create(:listing, :active)
      draft_listing     = create(:listing, status: :draft)

      create(:listing_view, user: user, listing: browsable_listing)
      create(:listing_view, user: user, listing: draft_listing)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(browsable_listing.id)
      expect(ids).not_to include(draft_listing.id)
    end

    it "excludes sold listings from the response" do
      active_listing = create(:listing, :active)
      sold_listing   = create(:listing, :sold)

      create(:listing_view, user: user, listing: active_listing)
      create(:listing_view, user: user, listing: sold_listing)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(active_listing.id)
      expect(ids).not_to include(sold_listing.id)
    end

    it "excludes reserved listings from the response" do
      active_listing    = create(:listing, :active)
      reserved_listing  = create(:listing, :reserved)

      create(:listing_view, user: user, listing: active_listing)
      create(:listing_view, user: user, listing: reserved_listing)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(active_listing.id)
      expect(ids).not_to include(reserved_listing.id)
    end

    it "excludes expired listings from the response" do
      active_listing  = create(:listing, :active)
      expired_listing = create(:listing, :expired)

      create(:listing_view, user: user, listing: active_listing)
      create(:listing_view, user: user, listing: expired_listing)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(active_listing.id)
      expect(ids).not_to include(expired_listing.id)
    end

    it "excludes admin-removed listings without raising a 500" do
      active_listing  = create(:listing, :active)
      removed_listing = create(:listing, :active, removed_at: 1.day.ago)

      create(:listing_view, user: user, listing: active_listing)
      create(:listing_view, user: user, listing: removed_listing)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(active_listing.id)
      expect(ids).not_to include(removed_listing.id)
    end

    it "a viewed-then-sold listing is filtered out cleanly (no 500)" do
      listing = create(:listing, :active)
      create(:listing_view, user: user, listing: listing)
      listing.sold!

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).not_to include(listing.id)
    end

    # ── Ordering ──────────────────────────────────────────────────────────────

    it "orders listings by last_viewed_at descending (most recently viewed first)" do
      old_listing   = create(:listing, :active)
      new_listing   = create(:listing, :active)

      create(:listing_view, user: user, listing: old_listing, last_viewed_at: 3.hours.ago)
      create(:listing_view, user: user, listing: new_listing, last_viewed_at: 1.hour.ago)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids.first).to eq(new_listing.id)
      expect(ids.last).to eq(old_listing.id)
    end

    # ── Pagination ────────────────────────────────────────────────────────────

    it "includes meta.pagination in the response" do
      get "/api/v1/my/viewed_listings", headers: headers, as: :json

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

    context "with more than one page of listings" do
      before do
        category = create(:category)
        30.times do |i|
          listing = create(:listing, :active, category: category)
          create(:listing_view, user: user, listing: listing, last_viewed_at: i.hours.ago)
        end
      end

      it "page 1 returns default page size with next_page set" do
        get "/api/v1/my/viewed_listings?page[number]=1", headers: headers, as: :json

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
        get "/api/v1/my/viewed_listings?page[number]=2", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listings"].length).to eq(10)
        pagination = body.dig("meta", "pagination")
        expect(pagination["current_page"]).to eq(2)
        expect(pagination["next_page"]).to be_nil
        expect(pagination["prev_page"]).to eq(1)
      end

      it "page 1 and page 2 ids are disjoint (no duplicates across pages)" do
        get "/api/v1/my/viewed_listings?page[number]=1", headers: headers, as: :json
        page1_ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }

        get "/api/v1/my/viewed_listings?page[number]=2", headers: headers, as: :json
        page2_ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }

        expect(page1_ids & page2_ids).to be_empty
      end
    end

    # ── Blocked-pair exclusion ────────────────────────────────────────────────

    it "excludes listings from users the current user has blocked" do
      blocked_seller  = create(:user)
      other_listing   = create(:listing, :active, user: blocked_seller)
      own_listing     = create(:listing, :active)

      create(:listing_view, user: user, listing: other_listing)
      create(:listing_view, user: user, listing: own_listing)
      create(:block, blocker: user, blocked: blocked_seller)

      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(own_listing.id)
      expect(ids).not_to include(other_listing.id)
    end
  end
end
