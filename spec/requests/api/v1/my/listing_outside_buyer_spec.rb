require "rails_helper"

# SF-B3 — "sold to someone not on Hatiwal" gets a real ledger row.
#
# It used to record nothing: `sold_with_buyer!` saw `clear_buyer: true`, cancelled
# any open reservation and returned nil, so `sold_units` moved while the ledger
# stayed silent. The sale was unviewable afterwards and there was nothing for the
# correction endpoint (SF-B4) to point at.
#
# THE TRAP THIS FILE EXISTS FOR: the seller's `sold_count` must move EXACTLY
# ONCE. Before SF-B3 the controller bumped it by hand
# (`bump_seller_sold_count_for_legacy_sale!`) precisely because no Transaction
# existed to do it. Now one always does — leaving the manual bump in place would
# have double-counted every single outside-buyer sale.
RSpec.describe "Api::V1::My::Listings outside-buyer sale (SF-B3)", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  describe "PUT /my/listings/:id/sold with clear_buyer" do
    it "creates exactly ONE sold transaction with a null buyer" do
      listing = create(:listing, :active, user: seller, price: 4000)

      expect do
        put "/api/v1/my/listings/#{listing.id}/sold",
            params: { clear_buyer: true }, headers: headers, as: :json
      end.to change(Transaction, :count).by(1)

      expect(response).to have_http_status(:ok)
      txn = listing.sale_transactions.sole
      expect(txn).to be_sold
      expect(txn.buyer_id).to be_nil
      expect(txn.seller_id).to eq(seller.id)
      expect(txn.final_price).to eq(4000)
      expect(txn.completed_at).to be_present
    end

    # The double-count trap, stated as a number.
    it "bumps the seller's sold_count exactly ONCE" do
      listing = create(:listing, :active, user: seller)

      expect do
        put "/api/v1/my/listings/#{listing.id}/sold",
            params: { clear_buyer: true }, headers: headers, as: :json
      end.to change { seller.reload.sold_count }.from(0).to(1)
    end

    it "credits nobody's bought_count — there is no buyer account to credit" do
      listing = create(:listing, :active, user: seller)
      bystander = create(:user)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      expect(bystander.reload.bought_count).to eq(0)
      expect(seller.reload.bought_count).to eq(0)
    end

    it "returns the transaction in the lifecycle response" do
      listing = create(:listing, :active, user: seller)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["transaction"]).to be_present
      expect(body["transaction"]["buyer"]).to be_nil
      expect(body["listing"]["sale"]["buyer"]).to be_nil
      expect(body["listing"]["sale"]["conversation_id"]).to be_nil
    end

    it "cancels an open hold rather than re-attributing the sale to that buyer" do
      listing = create(:listing, :active, user: seller)
      held_for = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: held_for)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: held_for.id }, headers: headers, as: :json

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      expect(listing.sale_transactions.reload.map(&:buyer_id)).to eq([ nil ])
      expect(held_for.reload.bought_count).to eq(0)
    end

    it "still moves ONE unit of a batch when no quantity is given" do
      listing = create(:listing, :active, user: seller, quantity: 50)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      listing.reload
      expect(listing.sold_units).to eq(1)
      expect(listing.available_units).to eq(49)
      expect(listing.status).to eq("active")
      expect(listing.sale_transactions.sole.quantity).to eq(1)
    end

    it "honours an explicit quantity and retires the listing when it empties the stock" do
      listing = create(:listing, :active, user: seller, quantity: 3)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true, quantity: 3 }, headers: headers, as: :json

      listing.reload
      expect(listing.sold_units).to eq(3)
      expect(listing.status).to eq("sold")
      expect(listing.sale_transactions.sole.quantity).to eq(3)
    end

    it "records one row per outside sale on a batch, not one row overwritten" do
      listing = create(:listing, :active, user: seller, quantity: 10)

      2.times do
        put "/api/v1/my/listings/#{listing.id}/sold",
            params: { clear_buyer: true, quantity: 2 }, headers: headers, as: :json
      end

      expect(listing.sale_transactions.reload.count).to eq(2)
      expect(listing.reload.sold_units).to eq(4)
      expect(seller.reload.sold_count).to eq(2)
    end
  end

  describe "GET /my/transactions" do
    it "returns the outside-buyer sale with buyer null instead of 500ing" do
      listing = create(:listing, :active, user: seller)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      get "/api/v1/my/transactions", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      row = JSON.parse(response.body)["transactions"].sole
      expect(row["buyer"]).to be_nil
      expect(row["seller"]["id"]).to eq(seller.id)
      expect(row["role"]).to eq("seller")
      expect(row["status"]).to eq("sold")
    end

    it "never leaks the buyer-less sale to another user" do
      listing = create(:listing, :active, user: seller)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      get "/api/v1/my/transactions", headers: auth_headers_for(create(:user)), as: :json

      expect(JSON.parse(response.body)["transactions"]).to eq([])
    end
  end

  describe "GET /my/reviews/pending" do
    # A prompt you cannot satisfy is worse than no prompt: Review's own
    # `belongs_to :reviewee` would 422 on submit.
    it "does not ask the seller to review a buyer who has no account" do
      listing = create(:listing, :active, user: seller)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true }, headers: headers, as: :json

      get "/api/v1/my/reviews/pending", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["transactions"]).to eq([])
    end

    it "still asks about a sale that DOES have a counterparty" do
      listing = create(:listing, :active, user: seller)
      buyer   = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id }, headers: headers, as: :json

      get "/api/v1/my/reviews/pending", headers: headers, as: :json

      expect(JSON.parse(response.body)["transactions"].length).to eq(1)
    end
  end

  describe "Transaction with a nil buyer" do
    it "is valid" do
      txn = build(:transaction, :outside_buyer)
      expect(txn).to be_valid
    end

    it "still requires the seller to be the listing's owner" do
      someone_elses = create(:listing, :active, user: create(:user))
      txn = build(:transaction, :outside_buyer, seller: seller, listing: someone_elses)

      expect(txn).not_to be_valid
      expect(txn.errors[:seller_id]).to be_present
    end
  end
end
