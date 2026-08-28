require "rails_helper"

# SF-B10 — `reserved_at` is "held since", and a HOLD is what dates it.
#
# The bug: the timestamp was written by a `before_save` keyed on the listing's
# STATUS (`reserved? && reserved_at.nil?`). A multi-unit batch deliberately keeps
# `status: active` while it holds units (SF-B2), so that condition never fired
# for a batch and `reserved_at` stayed nil for the entire time units were held —
# while `reserved_at` IS shipped on :seller_list and :owner_detailed. A seller's
# card could render "10 held for Ahmad" with no date on it.
#
# Third instance of one root cause: code reading `status == "reserved"` as
# evidence that a hold exists. So these specs assert on the HOLD (`held_units`,
# `sale`) and on `status` SEPARATELY — never one as a proxy for the other.
RSpec.describe "SF-B10 reserved_at is dated by the hold, not the status", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # A listing the seller can place a hold on: published, with a photo, and with a
  # conversation from `buyer` (Transaction validates the buyer is a participant).
  def sellable(quantity: 1)
    listing = create(:listing, :active, :with_image, user: seller, quantity: quantity)
    create(:conversation, listing: listing, buyer: buyer)
    listing
  end

  def reserve!(listing, quantity: nil)
    params = { buyer_id: buyer.id }
    params[:quantity] = quantity if quantity
    put "/api/v1/my/listings/#{listing.id}/reserve", params: params, headers: headers, as: :json
  end

  describe "a BATCH holding units — the reported bug" do
    it "carries a non-nil reserved_at while status stays active" do
      listing = sellable(quantity: 15)

      reserve!(listing, quantity: 10)
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)["listing"]
      # The two facts, asserted apart: the batch is still on the market...
      expect(body["status"]).to eq("active")
      # ...and it is holding units, which now has a date on it.
      expect(body["held_units"]).to eq(10)
      expect(body["reserved_at"]).to be_present
      expect(listing.reload.reserved_at).to be_present
    end

    it "dates the hold from the hold itself, not from the moment of the request" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)

      hold = listing.reload.open_transaction
      expect(hold).to be_reserved
      expect(listing.reserved_at.to_i).to eq(hold.created_at.to_i)
    end

    it "shows the date on the seller's My Listings row (:seller_list)" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)

      get "/api/v1/my/listings", headers: headers, as: :json
      row = JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }

      expect(row["status"]).to eq("active")
      expect(row["held_units"]).to eq(10)
      expect(row["sale"]["buyer"]["id"]).to eq(buyer.id)
      expect(row["reserved_at"]).to be_present
    end

    it "keeps the original date when the hold is advanced to another buyer" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)
      first_stamp = listing.reload.reserved_at

      other = create(:user)
      create(:conversation, listing: listing, buyer: other)
      put "/api/v1/my/listings/#{listing.id}/reserve",
          params: { buyer_id: other.id, quantity: 4 }, headers: headers, as: :json

      # Same hold row, moved — so it has been in place since it was created.
      expect(listing.reload.held_units).to eq(4)
      expect(listing.reserved_at.to_i).to eq(first_stamp.to_i)
    end
  end

  describe "a SINGLE-item hold — unchanged from before the fix" do
    it "still stamps reserved_at, and still flips the status to reserved" do
      listing = sellable

      reserve!(listing)
      body = JSON.parse(response.body)["listing"]

      expect(body["status"]).to eq("reserved")
      expect(body["held_units"]).to eq(1)
      expect(body["reserved_at"]).to be_present
      expect(listing.reload.reserved_at.to_i).to eq(listing.open_transaction.created_at.to_i)
    end

    it "stamps a legacy buyer-less reserve, which has no Transaction to date" do
      listing = sellable

      # The bare legacy call: no buyer_id, so nothing is written to the ledger and
      # `status: reserved` is the only record that a hold exists. The `before_save`
      # callback is deliberately kept for exactly this path.
      put "/api/v1/my/listings/#{listing.id}/reserve", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload).to be_reserved
      expect(listing.open_transaction).to be_nil
      expect(listing.reserved_at).to be_present
    end
  end

  describe "releasing a hold" do
    it "clears the date with the hold on a batch (status was never reserved)" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)
      expect(listing.reload.reserved_at).to be_present

      put "/api/v1/my/listings/#{listing.id}/activate", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)["listing"]
      expect(body["status"]).to eq("active")
      expect(body["held_units"]).to eq(0)
      # The mirror of the bug this ticket fixes: a "held since" for a hold that
      # nobody has any more would be just as wrong as a hold with no date.
      expect(body["reserved_at"]).to be_nil
      expect(listing.reload.reserved_at).to be_nil
    end

    it "clears the date on a single item, including a legacy buyer-less hold" do
      listing = sellable
      put "/api/v1/my/listings/#{listing.id}/reserve", headers: headers, as: :json
      expect(listing.reload.reserved_at).to be_present

      put "/api/v1/my/listings/#{listing.id}/activate", headers: headers, as: :json

      expect(listing.reload).to be_active
      expect(listing.reserved_at).to be_nil
    end

    it "clears the date when the listing is taken offline with a hold on it" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)

      put "/api/v1/my/listings/#{listing.id}/unpublish", headers: headers, as: :json

      expect(listing.reload).to be_draft
      expect(listing.held_units).to eq(0)
      expect(listing.reserved_at).to be_nil
    end

    it "re-dates the listing from the NEW hold when one is placed after a release" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)
      first_hold_id = listing.reload.open_transaction.id
      put "/api/v1/my/listings/#{listing.id}/activate", headers: headers, as: :json
      expect(listing.reload.reserved_at).to be_nil

      reserve!(listing, quantity: 3)

      listing.reload
      second_hold = listing.open_transaction
      # A genuinely new hold row, not the released one resurrected — and the date
      # is read off THAT row, so it always describes the hold in place now.
      expect(second_hold.id).not_to eq(first_hold_id)
      expect(listing.held_units).to eq(3)
      expect(listing.reserved_at.to_i).to eq(second_hold.created_at.to_i)
    end
  end

  describe "a hold that completes into a sale" do
    it "stops dating a hold once the held units are sold to that buyer" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)
      expect(listing.reload.reserved_at).to be_present

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 10 }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      listing.reload
      expect(listing.status).to eq("active")   # 5 of 15 left — still on the market
      expect(listing.held_units).to eq(0)
      expect(listing.reserved_at).to be_nil
      expect(listing.sold_at).to be_nil        # not sold out, so no sold_at either
    end

    it "keeps ANOTHER buyer's still-open hold dated after an unrelated sale" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 4)
      hold_stamp = listing.reload.reserved_at

      # A different buyer takes 3 units off the shelf; the first buyer's hold on
      # 4 units survives and must keep its date.
      other = create(:user)
      create(:conversation, listing: listing, buyer: other)
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: other.id, quantity: 3 }, headers: headers, as: :json

      listing.reload
      expect(listing.held_units).to eq(4)
      expect(listing.reserved_at.to_i).to eq(hold_stamp.to_i)
    end

    it "clears the date when 'Someone else / skip' cancels the hold" do
      listing = sellable(quantity: 15)
      reserve!(listing, quantity: 10)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true, quantity: 2 }, headers: headers, as: :json

      listing.reload
      expect(listing.held_units).to eq(0)
      expect(listing.reserved_at).to be_nil
    end

    it "clears the date when a sale leaves no stock for the hold to claim" do
      listing = sellable(quantity: 5)
      reserve!(listing, quantity: 4)
      expect(listing.reload.reserved_at).to be_present

      # Sold to an outside buyer: all 5 units go, so SF-B9's shrink destroys the
      # hold that can no longer be honoured — and its date must go with it.
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { clear_buyer: true, quantity: 5 }, headers: headers, as: :json

      listing.reload
      expect(listing.available_units).to eq(0)
      expect(listing.held_units).to eq(0)
      expect(listing.reserved_at).to be_nil
    end
  end

  describe "nothing stamps a listing that has no hold" do
    it "leaves reserved_at nil on publish" do
      listing = create(:listing, :with_image, user: seller)
      put "/api/v1/my/listings/#{listing.id}/publish", headers: headers, as: :json

      expect(listing.reload).to be_active
      expect(listing.reserved_at).to be_nil
    end

    it "leaves reserved_at nil when selling straight from active, no hold" do
      listing = sellable
      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id }, headers: headers, as: :json

      listing.reload
      expect(listing).to be_sold
      expect(listing.sold_at).to be_present
      expect(listing.reserved_at).to be_nil
    end

    it "leaves reserved_at nil on an ordinary edit" do
      listing = sellable(quantity: 15)
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "Edited title" } }, headers: headers, as: :json

      expect(listing.reload.title).to eq("Edited title")
      expect(listing.reserved_at).to be_nil
    end

    it "leaves reserved_at nil when a renewal touches an unheld listing" do
      listing = sellable(quantity: 15)
      put "/api/v1/my/listings/#{listing.id}/renew", headers: headers, as: :json

      expect(listing.reload.expires_at).to be_present
      expect(listing.reserved_at).to be_nil
    end
  end

  describe "the wire contract hatiwal-web depends on (card 285, not yet ported)" do
    # Web is still on the pre-redesign reserve-then-sold model and its e2e API
    # contract asserts the KEY `reserved_at` on the seller-list and detail
    # payloads. The key must survive whether the value is a date or nil — which
    # is why the column was kept rather than renamed to `held_since`.
    it "always ships the reserved_at key, held or not" do
      held = sellable(quantity: 15)
      reserve!(held, quantity: 2)
      free = sellable(quantity: 15)

      get "/api/v1/my/listings", headers: headers, as: :json
      rows = JSON.parse(response.body)["listings"]
      expect(rows.map { |r| r.key?("reserved_at") }).to all(be(true))

      get "/api/v1/my/listings/#{held.id}", headers: headers, as: :json
      expect(JSON.parse(response.body)["listing"]).to have_key("reserved_at")
      expect(JSON.parse(response.body)["listing"]["reserved_at"]).to be_present

      get "/api/v1/my/listings/#{free.id}", headers: headers, as: :json
      detail = JSON.parse(response.body)["listing"]
      expect(detail).to have_key("reserved_at")
      expect(detail["reserved_at"]).to be_nil
    end
  end
end
