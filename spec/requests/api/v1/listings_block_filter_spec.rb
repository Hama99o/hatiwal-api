require "rails_helper"

# Request specs covering the block-awareness of the listings index and show
# endpoints introduced in TASK-K852.
#
# Scenarios:
#   (a) viewer-blocked-seller  — viewer blocked seller X; X's listings hidden
#   (b) seller-blocked-viewer  — seller X blocked viewer; X's listings hidden
#   (c) guest                  — no auth token; sees all listings normally
#   (d) unrelated user         — no block relationship; sees all listings
#   (e) owner                  — can still view their own listing detail
RSpec.describe "Listings block filtering", type: :request do
  let(:viewer)  { create(:user) }
  let(:seller)  { create(:user) }
  let(:other)   { create(:user) }

  let!(:seller_listing) { create(:listing, :active, user: seller) }
  let!(:other_listing)  { create(:listing, :active, user: other) }

  def viewer_headers
    auth_headers_for(viewer)
  end

  def other_headers
    auth_headers_for(other)
  end

  # ── INDEX ────────────────────────────────────────────────────────────────

  describe "GET /api/v1/listings (index)" do
    def listing_ids
      JSON.parse(response.body)["listings"].map { |l| l["id"] }
    end

    context "(a) viewer has blocked seller" do
      before { create(:block, blocker: viewer, blocked: seller) }

      it "excludes the blocked seller's listing from the feed" do
        get "/api/v1/listings", headers: viewer_headers

        expect(response).to have_http_status(:ok)
        expect(listing_ids).not_to include(seller_listing.id)
      end

      it "still shows listings from unrelated sellers" do
        get "/api/v1/listings", headers: viewer_headers

        expect(listing_ids).to include(other_listing.id)
      end
    end

    context "(b) seller has blocked viewer" do
      before { create(:block, blocker: seller, blocked: viewer) }

      it "excludes the blocking seller's listing from the feed" do
        get "/api/v1/listings", headers: viewer_headers

        expect(response).to have_http_status(:ok)
        expect(listing_ids).not_to include(seller_listing.id)
      end

      it "still shows listings from unrelated sellers" do
        get "/api/v1/listings", headers: viewer_headers

        expect(listing_ids).to include(other_listing.id)
      end
    end

    context "(c) guest (no auth token)" do
      it "sees all active listings" do
        get "/api/v1/listings"

        expect(response).to have_http_status(:ok)
        expect(listing_ids).to include(seller_listing.id, other_listing.id)
      end
    end

    context "(d) unrelated authenticated user (no block relationship)" do
      it "sees all active listings" do
        get "/api/v1/listings", headers: other_headers

        expect(response).to have_http_status(:ok)
        expect(listing_ids).to include(seller_listing.id, other_listing.id)
      end
    end
  end

  # ── SHOW ─────────────────────────────────────────────────────────────────

  describe "GET /api/v1/listings/:id (show)" do
    context "(a) viewer has blocked seller" do
      before { create(:block, blocker: viewer, blocked: seller) }

      it "returns 404 for the blocked seller's listing" do
        get "/api/v1/listings/#{seller_listing.id}", headers: viewer_headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "(b) seller has blocked viewer" do
      before { create(:block, blocker: seller, blocked: viewer) }

      it "returns 404 for the blocking seller's listing" do
        get "/api/v1/listings/#{seller_listing.id}", headers: viewer_headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "(c) guest (no auth token)" do
      it "can view the listing detail" do
        get "/api/v1/listings/#{seller_listing.id}"

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listing"]["id"]).to eq(seller_listing.id)
      end
    end

    context "(d) unrelated authenticated user" do
      it "can view the listing detail" do
        get "/api/v1/listings/#{seller_listing.id}", headers: other_headers

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listing"]["id"]).to eq(seller_listing.id)
      end
    end

    context "(e) listing owner viewing their own listing" do
      let(:owner_headers) { auth_headers_for(seller) }

      it "can always view their own listing detail regardless of any block" do
        # Even if viewer blocked owner — ownership wins for the owner themselves
        create(:block, blocker: viewer, blocked: seller)

        get "/api/v1/listings/#{seller_listing.id}", headers: owner_headers

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["listing"]["id"]).to eq(seller_listing.id)
      end
    end
  end
end
