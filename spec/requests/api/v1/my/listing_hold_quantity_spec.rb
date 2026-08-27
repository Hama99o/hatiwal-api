require "rails_helper"

# SF-B2 — PUT /api/v1/my/listings/:id/reserve gains an optional `quantity`, and
# `held_units` puts that number on the wire.
#
# Before this a reservation was always `quantity: 1` (the column default)
# regardless of batch size, so "N held for Ahmad" could only ever read "1 held" —
# the number was a lie on any batch. `held_units` is the public-safe half: a
# count, never an identity.
RSpec.describe "Api::V1::My::Listings hold quantity (SF-B2)", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # The buyer picker only offers conversation participants, and Transaction
  # enforces it — mirror that here.
  def listing_with_buyer(quantity:)
    listing = create(:listing, :active, user: seller, quantity: quantity)
    create(:conversation, listing: listing, buyer: buyer)
    listing
  end

  describe "PUT reserve with a quantity" do
    it "stores the held units on a multi-unit listing" do
      listing = listing_with_buyer(quantity: 15)

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["transaction"]["quantity"]).to eq(2)
      expect(body["listing"]["held_units"]).to eq(2)
      expect(listing.reload.open_transaction.quantity).to eq(2)
    end

    it "defaults to holding ONE unit of a batch when no quantity is given" do
      listing = listing_with_buyer(quantity: 15)

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id }, headers: headers, as: :json

      expect(JSON.parse(response.body)["listing"]["held_units"]).to eq(1)
    end

    it "clamps a hold that exceeds the available stock — a stale client cannot over-hold" do
      listing = listing_with_buyer(quantity: 3)

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 99 }, headers: headers, as: :json

      expect(JSON.parse(response.body)["listing"]["held_units"]).to eq(3)
    end

    it "ignores the quantity param on a SINGLE-item listing — there is one unit to hold" do
      listing = listing_with_buyer(quantity: 1)

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 7 }, headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["transaction"]["quantity"]).to eq(1)
      expect(body["listing"]["held_units"]).to eq(1)
      expect(listing.reload.status).to eq("reserved")
    end

    it "updates the held units when the seller re-reserves a batch" do
      listing = listing_with_buyer(quantity: 15)

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json
      first_txn_id = JSON.parse(response.body)["transaction"]["id"]

      expect do
        put "/api/v1/my/listings/#{listing.id}/reserve",
            params: { buyer_id: buyer.id, quantity: 5 }, headers: headers, as: :json
      end.not_to change(Transaction, :count)

      body = JSON.parse(response.body)
      expect(body["transaction"]["id"]).to eq(first_txn_id)
      expect(body["listing"]["held_units"]).to eq(5)
    end

    it "leaves available_units untouched — a hold is advisory, not inventory set aside" do
      listing = listing_with_buyer(quantity: 15)

      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      body = JSON.parse(response.body)["listing"]
      expect(body["available_units"]).to eq(15)
      expect(body["held_units"]).to eq(2)
    end
  end

  describe "held_units on the wire" do
    it "is 0 on a listing with no hold" do
      listing = listing_with_buyer(quantity: 15)

      get "/api/v1/listings/#{listing.id}", as: :json

      expect(JSON.parse(response.body)["listing"]["held_units"]).to eq(0)
    end

    it "is present on the public :detailed view without leaking the buyer's identity" do
      listing = listing_with_buyer(quantity: 15)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 4 }, headers: headers, as: :json

      get "/api/v1/listings/#{listing.id}", as: :json

      body = JSON.parse(response.body)["listing"]
      expect(body["held_units"]).to eq(4)
      expect(body).not_to have_key("sale")
      expect(response.body).not_to include(buyer.firstname)
    end

    it "is present on the public :list view (the feed card reads the same number)" do
      listing = listing_with_buyer(quantity: 15)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 4 }, headers: headers, as: :json

      get "/api/v1/listings", as: :json

      row = JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }
      expect(row["held_units"]).to eq(4)
      expect(row).not_to have_key("sale")
    end

    it "drops back to 0 once the hold is released" do
      listing = listing_with_buyer(quantity: 1)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id }, headers: headers, as: :json
      put "/api/v1/my/listings/#{listing.id}/activate", headers: headers, as: :json

      expect(JSON.parse(response.body)["listing"]["held_units"]).to eq(0)
    end

    # The N+1 this field could easily reintroduce: an association scope always
    # hits the database, so `held_units` MUST read the eager-loaded array.
    #
    # Measured as "same rows, holds added" rather than "more rows": the public
    # feed already carries a per-row cost for the seller/category/thumbnail
    # fields it has always rendered, and this spec is about what THIS field adds
    # on top — which must be nothing.
    it "adds no query per held row to the public feed" do
      listings = Array.new(3) do
        l = create(:listing, :active, user: seller, quantity: 5)
        create(:conversation, listing: l, buyer: buyer)
        l
      end
      get "/api/v1/listings", as: :json # warm caches

      counter = lambda do |ref, &block|
        ActiveSupport::Notifications.subscribed(
          lambda { |*, payload|
            sql = payload[:sql].to_s
            next if sql.start_with?("SAVEPOINT", "RELEASE SAVEPOINT")
            next if sql =~ /\AUPDATE "users" SET "tokens"/

            ref[0] += 1
          },
          "sql.active_record",
          &block
        )
      end

      without_holds = [ 0 ]
      counter.call(without_holds) { get "/api/v1/listings", as: :json }

      listings.each do |l|
        put "/api/v1/my/listings/#{l.id}/reserve",
            params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json
      end

      with_holds = [ 0 ]
      counter.call(with_holds) { get "/api/v1/listings", as: :json }

      # Sanity: the field really is populated, so this is not a vacuous pass.
      expect(JSON.parse(response.body)["listings"].map { |l| l["held_units"] }).to all(eq(2))
      expect(with_holds[0]).to eq(without_holds[0]),
        "Expected held_units to cost no extra query (no N+1): " \
        "#{without_holds[0]} queries with 0 holds, #{with_holds[0]} with 3"
    end
  end

  describe "current_sale on an ACTIVE multi-unit listing with a hold" do
    # The bug SF-B2 fixes: `current_sale` was gated on `reserved? || sold?`, and a
    # multi-unit listing deliberately keeps status `active` while units are held —
    # so the seller's own card showed no buyer for a hold they had just placed.
    it "surfaces the hold's buyer on the owner's detail view" do
      listing = listing_with_buyer(quantity: 15)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json

      sale = JSON.parse(response.body)["listing"]["sale"]
      expect(listing.reload.status).to eq("active")
      expect(sale).to be_present
      expect(sale["status"]).to eq("reserved")
      expect(sale["quantity"]).to eq(2)
      expect(sale["buyer"]["id"]).to eq(buyer.id)
    end

    it "surfaces the hold on the seller's list row too" do
      listing = listing_with_buyer(quantity: 15)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      get "/api/v1/my/listings", headers: headers, as: :json

      row = JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }
      expect(row["sale"]["quantity"]).to eq(2)
      expect(row["sale"]["buyer"]["id"]).to eq(buyer.id)
    end
  end
end
