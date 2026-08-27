require "rails_helper"

# SF-B4 — undo & edit a recorded sale.
#
# The hole this closes (docs/SELL_FLOW_AUDIT.md §4): a seller who tapped
# "sold 5" on a batch of 15 instead of "sold 1" had permanently lost 4 units of
# stock, with no in-app recourse. `record_units_sold!` only ever added, the trust
# counters were increment-only, and a sold-out listing was terminal.
#
#   PATCH  /api/v1/my/transactions/:id  { quantity?, buyer_id?, clear_buyer?, final_price? }
#   DELETE /api/v1/my/transactions/:id
RSpec.describe "Api::V1::My::Transactions corrections (SF-B4)", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:buyer2)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # Records a real sale through the real endpoint, so every spec below starts
  # from state the app can actually produce.
  def sell!(quantity:, units:, buyer_for: nil, clear_buyer: false)
    listing = create(:listing, :active, user: seller, quantity: quantity, price: 1000)
    [ buyer_for, buyer, buyer2 ].compact.uniq.each do |b|
      create(:conversation, listing: listing, seller: seller, buyer: b)
    end
    params = { quantity: units }
    params[:buyer_id]    = buyer_for.id if buyer_for
    params[:clear_buyer] = true if clear_buyer

    put "/api/v1/my/listings/#{listing.id}/sold", params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)

    [ listing.reload, listing.sale_transactions.sold.order(:created_at).last ]
  end

  # ── The headline case from the audit ────────────────────────────────────────
  describe "correcting 5 -> 1 on a batch" do
    it "restores 4 units of stock AND flips a sold listing back to active" do
      listing, txn = sell!(quantity: 5, units: 5, buyer_for: buyer)
      expect(listing.status).to eq("sold")
      expect(listing.sold_units).to eq(5)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 1 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.sold_units).to eq(1)
      expect(listing.available_units).to eq(4)
      expect(listing.status).to eq("active")
      expect(txn.reload.quantity).to eq(1)
    end

    it "clears sold_at so the card stops claiming a sale date for a live listing" do
      listing, txn = sell!(quantity: 5, units: 5, buyer_for: buyer)
      expect(listing.sold_at).to be_present

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 1 }, headers: headers, as: :json

      expect(listing.reload.sold_at).to be_nil
    end

    it "puts the re-opened listing back in the buyer feed" do
      listing, txn = sell!(quantity: 5, units: 5, buyer_for: buyer)
      expect(Listing.browsable).not_to include(listing)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 1 }, headers: headers, as: :json

      expect(Listing.browsable).to include(listing.reload)
    end

    it "returns the repainted listing and transaction in one response" do
      _listing, txn = sell!(quantity: 5, units: 5, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 1 }, headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["listing"]["status"]).to eq("active")
      expect(body["listing"]["available_units"]).to eq(4)
      expect(body["listing"]["sale"]["quantity"]).to eq(1)
      expect(body["transaction"]["quantity"]).to eq(1)
    end

    it "retires the listing again when a correction UPWARDS empties the stock" do
      listing, txn = sell!(quantity: 5, units: 1, buyer_for: buyer)
      expect(listing.status).to eq("active")

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 5 }, headers: headers, as: :json

      listing.reload
      expect(listing.sold_units).to eq(5)
      expect(listing.status).to eq("sold")
    end
  end

  # ── Voiding ────────────────────────────────────────────────────────────────
  describe "DELETE (void)" do
    it "returns the listing to active with sold_units 0" do
      listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)
      expect(listing.status).to eq("sold")

      delete "/api/v1/my/transactions/#{txn.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.status).to eq("active")
      expect(listing.sold_units).to eq(0)
      expect(Transaction.exists?(txn.id)).to be(false)
      expect(JSON.parse(response.body)).not_to have_key("transaction")
    end

    it "decrements the seller's sold_count and the buyer's bought_count" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)
      expect(seller.reload.sold_count).to eq(1)
      expect(buyer.reload.bought_count).to eq(1)

      delete "/api/v1/my/transactions/#{txn.id}", headers: headers, as: :json

      expect(seller.reload.sold_count).to eq(0)
      expect(buyer.reload.bought_count).to eq(0)
    end

    it "never drives a counter below zero, even when it was already repaired to 0" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)
      seller.update_columns(sold_count: 0)
      buyer.update_columns(bought_count: 0)

      delete "/api/v1/my/transactions/#{txn.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(seller.reload.sold_count).to eq(0)
      expect(buyer.reload.bought_count).to eq(0)
    end

    it "gives back only this sale's units on a batch with several buyers" do
      listing = create(:listing, :active, user: seller, quantity: 10, price: 1000)
      [ buyer, buyer2 ].each { |b| create(:conversation, listing: listing, seller: seller, buyer: b) }
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 3 }, headers: headers, as: :json
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer2.id, quantity: 4 }, headers: headers, as: :json
      expect(listing.reload.sold_units).to eq(7)
      first_sale = listing.sale_transactions.find_by(buyer_id: buyer.id)

      delete "/api/v1/my/transactions/#{first_sale.id}", headers: headers, as: :json

      listing.reload
      expect(listing.sold_units).to eq(4)
      expect(listing.sales_count).to eq(1)
      expect(buyer.reload.bought_count).to eq(0)
      expect(buyer2.reload.bought_count).to eq(1)
      expect(seller.reload.sold_count).to eq(1)
    end

    it "voids an outside-buyer sale too — the row SF-B3 created is correctable" do
      listing, txn = sell!(quantity: 1, units: 1, clear_buyer: true)
      expect(txn.buyer_id).to be_nil

      delete "/api/v1/my/transactions/#{txn.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.status).to eq("active")
      expect(seller.reload.sold_count).to eq(0)
    end

    it "PATCH with quantity 0 voids through the same endpoint" do
      listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 0 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Transaction.exists?(txn.id)).to be(false)
      expect(listing.reload.status).to eq("active")
    end
  end

  # ── Reassigning the buyer ──────────────────────────────────────────────────
  describe "PATCH buyer_id / clear_buyer / final_price" do
    it "moves bought_count from the wrong buyer to the right one" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { buyer_id: buyer2.id }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(txn.reload.buyer_id).to eq(buyer2.id)
      expect(buyer.reload.bought_count).to eq(0)
      expect(buyer2.reload.bought_count).to eq(1)
      expect(seller.reload.sold_count).to eq(1)
    end

    it "reassigns to 'not on Hatiwal' with clear_buyer, releasing the buyer's count" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { clear_buyer: true }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(txn.reload.buyer_id).to be_nil
      expect(buyer.reload.bought_count).to eq(0)
      expect(JSON.parse(response.body)["transaction"]["buyer"]).to be_nil
    end

    it "corrects the price without touching any counter" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { final_price: 750 }, headers: headers, as: :json

      expect(txn.reload.final_price).to eq(750)
      expect(seller.reload.sold_count).to eq(1)
      expect(buyer.reload.bought_count).to eq(1)
    end

    it "refuses a buyer who never had a conversation on the listing" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)
      stranger = create(:user)

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { buyer_id: stranger.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
      expect(txn.reload.buyer_id).to eq(buyer.id)
    end
  end

  # ── The capacity clamp ─────────────────────────────────────────────────────
  describe "capacity" do
    it "422s when the corrected quantity exceeds what the listing can hold" do
      listing, txn = sell!(quantity: 5, units: 2, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 99 }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
      expect(listing.reload.sold_units).to eq(2)
      expect(txn.reload.quantity).to eq(2)
    end

    it "counts the OTHER sales when computing capacity" do
      listing = create(:listing, :active, user: seller, quantity: 10, price: 1000)
      [ buyer, buyer2 ].each { |b| create(:conversation, listing: listing, seller: seller, buyer: b) }
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 3 }, headers: headers, as: :json
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer2.id, quantity: 4 }, headers: headers, as: :json
      first_sale = listing.sale_transactions.find_by(buyer_id: buyer.id)

      # 10 total, 4 committed to the other buyer => this sale may grow to 6.
      patch "/api/v1/my/transactions/#{first_sale.id}", params: { quantity: 6 }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(listing.reload.sold_units).to eq(10)
      expect(listing.status).to eq("sold")

      patch "/api/v1/my/transactions/#{first_sale.id}", params: { quantity: 7 }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(listing.reload.sold_units).to eq(10)
    end

    it "never leaves sold_units outside the DB check constraint" do
      listing, txn = sell!(quantity: 3, units: 3, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 4 }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      listing.reload
      expect(listing.sold_units).to be_between(0, listing.quantity)
    end
  end

  # ── The one deliberate refusal ─────────────────────────────────────────────
  describe "a sale that already has a review" do
    def reviewed_sale
      _listing, txn = sell!(quantity: 5, units: 2, buyer_for: buyer)
      create(:review, sale: txn, reviewer: seller, reviewee: buyer, role: :of_buyer)
      txn
    end

    it "refuses to void it, with a machine-readable code and no change" do
      txn = reviewed_sale
      listing = txn.listing

      delete "/api/v1/my/transactions/#{txn.id}", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["code"]).to eq("sale_has_review")
      expect(body["error"]).to be_present
      expect(Transaction.exists?(txn.id)).to be(true)
      expect(listing.reload.sold_units).to eq(2)
      expect(seller.reload.sold_count).to eq(1)
      expect(buyer.reload.bought_count).to eq(1)
    end

    it "refuses to reassign its buyer, and leaves the review attached" do
      txn = reviewed_sale

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { buyer_id: buyer2.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["code"]).to eq("sale_has_review")
      expect(txn.reload.buyer_id).to eq(buyer.id)
      expect(txn.reviews.count).to eq(1)
      expect(buyer2.reload.bought_count).to eq(0)
    end

    it "refuses clear_buyer on it too — that is a reassignment" do
      txn = reviewed_sale

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { clear_buyer: true }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(txn.reload.buyer_id).to eq(buyer.id)
    end

    it "STILL ALLOWS fixing its quantity — a typo is not a reason to lose a review" do
      txn = reviewed_sale
      listing = txn.listing

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 1 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(txn.reload.quantity).to eq(1)
      expect(txn.reviews.count).to eq(1)
      expect(listing.reload.sold_units).to eq(1)
    end

    it "STILL ALLOWS fixing its price" do
      txn = reviewed_sale

      patch "/api/v1/my/transactions/#{txn.id}", params: { final_price: 500 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(txn.reload.final_price).to eq(500)
    end
  end

  # ── Authorization ─────────────────────────────────────────────────────────
  describe "authorization" do
    it "requires authentication" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      patch "/api/v1/my/transactions/#{txn.id}", params: { quantity: 0 }, as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "/api/v1/my/transactions/#{txn.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for a user who is party to neither side" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      delete "/api/v1/my/transactions/#{txn.id}", headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:not_found)
      expect(Transaction.exists?(txn.id)).to be(true)
    end

    # The buyer can see the sale (it is theirs too) but must never be able to
    # edit or erase the seller's ledger entry.
    it "403s for the BUYER of the sale" do
      _listing, txn = sell!(quantity: 1, units: 1, buyer_for: buyer)

      delete "/api/v1/my/transactions/#{txn.id}", headers: auth_headers_for(buyer), as: :json
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/my/transactions/#{txn.id}",
            params: { quantity: 0 }, headers: auth_headers_for(buyer), as: :json
      expect(response).to have_http_status(:forbidden)

      expect(Transaction.exists?(txn.id)).to be(true)
    end

    it "403s on a still-RESERVED transaction — releasing a hold is /activate" do
      listing = create(:listing, :active, user: seller, quantity: 5)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json
      hold = listing.reload.open_transaction

      delete "/api/v1/my/transactions/#{hold.id}", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Transaction.exists?(hold.id)).to be(true)
    end

    it "404s for a transaction id that does not exist" do
      delete "/api/v1/my/transactions/999999", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
