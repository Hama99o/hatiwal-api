require "rails_helper"

# PUT /api/v1/my/listings/:id/sold with a quantity.
#
# The behaviour that matters end to end: selling SOME of the stock must leave the
# listing active and in the feed, and selling the LAST of it must retire it
# exactly as a single-item sale does today.
RSpec.describe "Api::V1::My::Listings quantity", type: :request do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:other_buyer) { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # The buyer picker only offers conversation participants, and Transaction
  # enforces it — mirror that here.
  def listing_with_buyers(quantity:, buyers:)
    listing = create(:listing, user: seller, status: :active, quantity: quantity)
    buyers.each { |b| create(:conversation, listing: listing, buyer: b) }
    listing
  end

  describe "a partial sale" do
    it "keeps the listing ACTIVE and browsable — the feed must not lose it" do
      listing = listing_with_buyers(quantity: 15, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 3 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.status).to eq("active")
      expect(listing.sold_units).to eq(3)
      expect(listing.available_units).to eq(12)
      expect(Listing.browsable).to include(listing)
    end

    it "records who bought how many" do
      listing = listing_with_buyers(quantity: 15, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 3 }, headers: headers, as: :json

      txn = listing.sale_transactions.sole
      expect(txn.buyer_id).to eq(buyer.id)
      expect(txn.quantity).to eq(3)
      expect(txn.status).to eq("sold")
    end

    it "reports the remaining stock back to the client" do
      listing = listing_with_buyers(quantity: 15, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 4 }, headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body.dig("listing", "available_units")).to eq(11)
      expect(body.dig("listing", "status")).to eq("active")
    end
  end

  describe "selling the last of the stock" do
    it "retires the listing, exactly as a single-item sale does" do
      listing = listing_with_buyers(quantity: 2, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      listing.reload
      expect(listing.status).to eq("sold")
      expect(listing.available_units).to eq(0)
      expect(Listing.browsable).not_to include(listing)
    end

    it "sells ONE unit when no quantity is sent, not the whole batch" do
      # REVERSED, and the report that reversed it: a seller with 50 in stock marked one
      # sale to someone not on Hatiwal and the listing came back "Sold — 0 of 50 left".
      # Defaulting to the whole shelf makes the destructive outcome the silent one, in a
      # product with no payments and no undo. "I sold all 50" is a deliberate act and is
      # sent explicitly; saying nothing now means one unit.
      #
      # This also covers clients that predate the quantity field: an old build marking a
      # batch sold moves one unit instead of destroying the stock.
      listing = create(:listing, user: seller, status: :active, quantity: 15)

      put "/api/v1/my/listings/#{listing.id}/sold", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.sold_units).to eq(1)
      expect(listing.available_units).to eq(14)
      expect(listing.status).to eq("active")
    end

    it "sells the whole batch when the seller says so explicitly" do
      listing = create(:listing, user: seller, status: :active, quantity: 15)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { quantity: 15 }, headers: headers, as: :json

      listing.reload
      expect(listing.available_units).to eq(0)
      expect(listing.status).to eq("sold")
    end

    it "honours the count on a sale to someone NOT on Hatiwal" do
      # The path that lost the stock. `sold_with_buyer!` returns nil the moment
      # clear_buyer is set — before it looks at quantity — so there is no transaction to
      # read the count off and the controller has to use the request's own number.
      listing = create(:listing, user: seller, status: :active, quantity: 50)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true, quantity: 1 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.sold_units).to eq(1)
      expect(listing.available_units).to eq(49)
      expect(listing.status).to eq("active")
    end
  end

  describe "reserving part of a batch" do
    # Reported from a device, and the seller's question was the right one: "when it's
    # reserved other people cannot buy — how will people buy it?" `reserved` is a
    # whole-listing state and `browsable` is active-only, so holding ONE packet hid all
    # fifty from every buyer.
    it "keeps the listing ACTIVE and browsable, so the rest is still for sale" do
      listing = listing_with_buyers(quantity: 50, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.status).to eq("active")
      expect(Listing.browsable).to include(listing)
    end

    it "still takes a SINGLE-item listing off the market, which is what reserving means there" do
      listing = listing_with_buyers(quantity: 1, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id }, headers: headers, as: :json

      listing.reload
      expect(listing.status).to eq("reserved")
      expect(Listing.browsable).not_to include(listing)
    end
  end

  describe "two buyers on one listing" do
    it "keeps a separate sale per buyer and retires it on the one that empties it" do
      listing = listing_with_buyers(quantity: 5, buyers: [ buyer, other_buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json
      expect(listing.reload.status).to eq("active")

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: other_buyer.id, quantity: 3 }, headers: headers, as: :json

      listing.reload
      expect(listing.status).to eq("sold")
      sales = listing.sale_transactions
      expect(sales.count).to eq(2)
      expect(sales.map(&:quantity).sort).to eq([ 2, 3 ])
      expect(sales.map(&:buyer_id)).to contain_exactly(buyer.id, other_buyer.id)
    end
  end

  describe "the single-unit path is untouched" do
    it "behaves exactly as before — sold, archived, one transaction of 1 unit" do
      listing = listing_with_buyers(quantity: 1, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id }, headers: headers, as: :json

      listing.reload
      expect(listing.status).to eq("sold")
      expect(listing.sale_transactions.sole.quantity).to eq(1)
    end
  end

  describe "a stale client cannot oversell" do
    it "clamps to what is actually left" do
      listing = listing_with_buyers(quantity: 3, buyers: [ buyer ])

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 99 }, headers: headers, as: :json

      listing.reload
      expect(listing.sold_units).to eq(3)
      expect(listing.sale_transactions.sole.quantity).to eq(3)
    end
  end

  describe "creating a listing with a quantity" do
    it "accepts it" do
      post "/api/v1/my/listings",
           params: { listing: attributes_for(:listing).merge(
             category_id: create(:category).id, quantity: 12
           ) }, headers: headers, as: :json

      expect(response).to have_http_status(:created).or have_http_status(:ok)
      expect(Listing.last.quantity).to eq(12)
    end

    it "defaults to 1 when the seller does not mention it" do
      post "/api/v1/my/listings",
           params: { listing: attributes_for(:listing).merge(category_id: create(:category).id) },
           headers: headers, as: :json

      expect(Listing.last.quantity).to eq(1)
    end

    it "rejects a quantity below 1" do
      post "/api/v1/my/listings",
           params: { listing: attributes_for(:listing).merge(
             category_id: create(:category).id, quantity: 0
           ) }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
