require "rails_helper"

# SF-B1 — "a reserved listing stays on the market."
#
# Before this, `Listing.browsable` was `active.not_expired.not_removed`, so the
# moment a seller held a single-item listing for a buyer it vanished from the
# feed, from search, from the category counts and from the similar-listings rail,
# with nothing telling the seller why (docs/SELL_FLOW_AUDIT.md §7). It is now
# `live.not_expired.not_removed` — the badge, not the absence, communicates the
# hold.
#
# The whole point is the pairing: back in search AND messageable. Shipping only
# the first half would be worse than the old behaviour (found via search, then
# hit a wall), so both halves are asserted here in one file.
RSpec.describe "Reserved listing visibility (SF-B1)", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:headers) { auth_headers_for(buyer) }

  describe "GET /api/v1/listings" do
    it "returns a reserved listing in the buyer feed" do
      reserved = create(:listing, :reserved, user: seller)

      get "/api/v1/listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(reserved.id)
    end

    it "returns a reserved listing for a guest too (the feed is public)" do
      reserved = create(:listing, :reserved, user: seller)

      get "/api/v1/listings", as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(reserved.id)
    end

    it "finds a reserved listing by search term" do
      reserved = create(:listing, :reserved, user: seller, title: "Blue Herat Carpet")
      create(:listing, :active, user: seller, title: "Red Kabul Bicycle")

      get "/api/v1/listings", params: { search: "herat carpet" }, headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ reserved.id ])
    end

    it "still hides sold, draft, expired and admin-removed listings" do
      sold    = create(:listing, :sold,     user: seller)
      draft   = create(:listing, :draft,    user: seller)
      expired = create(:listing, :expired,  user: seller)
      removed = create(:listing, :reserved, user: seller, removed_at: Time.current)

      get "/api/v1/listings", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).not_to include(sold.id, draft.id, expired.id, removed.id)
    end
  end

  describe "POST /api/v1/listings/:listing_id/conversations" do
    it "lets a non-owner message a reserved listing" do
      reserved = create(:listing, :reserved, user: seller)

      expect do
        post "/api/v1/listings/#{reserved.id}/conversations",
             params: { message: "Is this still up for grabs?" }, headers: headers, as: :json
      end.to change(Conversation, :count).by(1).and change(Message, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["conversation"]["id"]).to be_present
    end

    # The pairing the ticket turns on: the exact listing the feed just handed the
    # buyer must be one they can act on.
    it "makes every listing the feed returns messageable" do
      create(:listing, :reserved, user: seller)

      get "/api/v1/listings", headers: headers, as: :json
      feed_id = JSON.parse(response.body)["listings"].first["id"]

      post "/api/v1/listings/#{feed_id}/conversations",
           params: { message: "Still available?" }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "still forbids messaging a sold listing" do
      sold = create(:listing, :sold, user: seller)

      post "/api/v1/listings/#{sold.id}/conversations",
           params: { message: "hi" }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/my/listings?status=active" do
    it "includes the seller's held listings in the Active tab" do
      own_headers = auth_headers_for(seller)
      active   = create(:listing, :active,   user: seller)
      reserved = create(:listing, :reserved, user: seller)

      get "/api/v1/my/listings", params: { status: "active" }, headers: own_headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to contain_exactly(active.id, reserved.id)
    end

    it "still answers ?status=reserved with exactly the reserved rows" do
      own_headers = auth_headers_for(seller)
      create(:listing, :active, user: seller)
      reserved = create(:listing, :reserved, user: seller)

      get "/api/v1/my/listings", params: { status: "reserved" }, headers: own_headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ reserved.id ])
    end
  end

  describe "public profile counts" do
    it "counts a held listing in listings_count, matching the grid under the header" do
      create(:listing, :active,   user: seller)
      create(:listing, :reserved, user: seller)
      create(:listing, :sold,     user: seller)

      get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

      expect(JSON.parse(response.body)["user"]["listings_count"]).to eq(2)
    end

    it "counts a held listing in the owner's own items_active_count" do
      own_headers = auth_headers_for(seller)
      create(:listing, :active,   user: seller)
      create(:listing, :reserved, user: seller)

      get "/api/v1/users/me", headers: own_headers, as: :json

      expect(JSON.parse(response.body)["user"]["items_active_count"]).to eq(2)
    end
  end
end
