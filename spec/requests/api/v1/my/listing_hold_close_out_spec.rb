require "rails_helper"

# SF-B9 — PUT /api/v1/my/listings/:id/sold must close out the listing's OWN open
# hold.
#
# The bug, measured on a live probe rather than reasoned about: a seller holds 10
# of a 15-unit batch for Ahmad, then sells those same 10 units to Ahmad. The
# listing kept BOTH rows — [["reserved", 10], ["sold", 10]] — and a buyer opening
# it read "5 available · 10 held": ten units still on hold for a person who had
# already bought them.
#
# Root cause, in Listing#sold_with_buyer!:
#
#     existing = reserved? ? open_transaction : nil
#
# The gate read the LISTING'S STATUS as a proxy for "is a hold in progress". That
# was true while placing a hold always flipped the status to `reserved`, and
# stopped being true when SF-B2 made a multi-unit batch deliberately stay
# `active` while units are held ("a batch does not leave the market because one
# unit is held"). For every batch `existing` was then always nil, so the
# legitimate close-out never happened. Single-item listings were unaffected —
# they do flip — which is why the whole thing hid behind the quantity feature.
#
# Knock-on the fix also clears: the phantom hold set SF-B8's quantity floor, so
# the seller above could not lower `quantity` to 6 — refused on account of 10
# units held that no longer existed.
#
# The fix gates the close-out on "is there an open hold FOR THIS BUYER"
# (Listing#hold_closed_by_sale) instead of on the listing's status, which keeps
# TASK-TX02's protection intact: a hold belonging to a DIFFERENT buyer is never
# re-attributed to this sale, and a buyer-less sale still only closes out a
# listing that is genuinely `reserved` right now.
RSpec.describe "Api::V1::My::Listings hold close-out (SF-B9)", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:other)   { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  # The buyer picker only offers conversation participants, and Transaction
  # enforces it — so the conversations are setup, not decoration.
  def batch(quantity:, buyers: [ buyer ])
    listing = create(:listing, :active, user: seller, quantity: quantity)
    buyers.each { |b| create(:conversation, listing: listing, buyer: b) }
    listing
  end

  # Always through the HTTP path: `sold_units` is moved by the CONTROLLER
  # (record_units_sold!), so a model-only exercise of these flows reports
  # `sold_units: 0` and proves nothing about what a buyer sees.
  def hold!(listing, for_buyer: buyer, units: nil)
    params = { buyer_id: for_buyer.id }
    params[:quantity] = units if units
    put "/api/v1/my/listings/#{listing.id}/reserve", params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    listing.reload
  end

  def sell!(listing, **params)
    put "/api/v1/my/listings/#{listing.id}/sold", params: params, headers: headers, as: :json
  end

  # ── The repro from the card ──────────────────────────────────────────────────
  describe "selling a batch's held units to the buyer holding them" do
    it "closes out the hold instead of leaving it open beside the sale" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)
      expect(listing.held_units).to eq(10)

      # The hold row is ADVANCED, not duplicated: no new Transaction.
      expect { sell!(listing, buyer_id: buyer.id, quantity: 10) }
        .not_to change(Transaction, :count)

      expect(response).to have_http_status(:ok)
      listing.reload
      # Exactly one row, and it is the sale.
      txn = listing.sale_transactions.sole
      expect(txn).to be_sold
      expect(txn.buyer_id).to eq(buyer.id)
      expect(txn.quantity).to eq(10)
      expect(txn.completed_at).to be_present
      # No surviving hold.
      expect(listing.open_transaction).to be_nil
      expect(listing.held_units).to eq(0)
      # Stock adds up: 10 of 15 gone, 5 left, still on the market.
      expect(listing.sold_units).to eq(10)
      expect(listing.available_units).to eq(5)
      expect(listing.status).to eq("active")
    end

    it "stops a buyer being shown '5 available · 10 held' for units already sold to them" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)
      sell!(listing, buyer_id: buyer.id, quantity: 10)

      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(buyer), as: :json

      body = JSON.parse(response.body)["listing"]
      expect(body["available_units"]).to eq(5)
      expect(body["held_units"]).to eq(0)
      expect(body["available_units"]).to be >= body["held_units"]
    end

    it "reports the closed-out hold back on the lifecycle response itself" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)
      hold_id = listing.open_transaction.id

      sell!(listing, buyer_id: buyer.id, quantity: 10)

      body = JSON.parse(response.body)
      # Same row, now sold — the client's open "held for Ahmad" card becomes the
      # sale rather than being joined by a second one.
      expect(body["transaction"]["id"]).to eq(hold_id)
      expect(body["transaction"]["status"]).to eq("sold")
      expect(body["listing"]["held_units"]).to eq(0)
      expect(body["listing"]["available_units"]).to eq(5)
    end

    it "leaves the listing re-holdable — no second open hold, no orphan" do
      listing = batch(quantity: 15, buyers: [ buyer, other ])
      hold!(listing, units: 10)
      sell!(listing, buyer_id: buyer.id, quantity: 10)
      expect(listing.reload.held_units).to eq(0)

      # Only one open hold per listing is possible at all
      # (index_transactions_on_listing_id_while_open, UNIQUE WHERE status = 0),
      # so a surviving phantom would either be silently handed to `other` or
      # blow up here.
      hold!(listing, for_buyer: other, units: 3)

      expect(listing.sale_transactions.reserved.count).to eq(1)
      expect(listing.open_transaction.buyer_id).to eq(other.id)
      expect(listing.held_units).to eq(3)
      expect(listing.available_units).to eq(5)
    end

    it "closes out only PART of a hold when the seller sells fewer units than they held" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)

      expect { sell!(listing, buyer_id: buyer.id, quantity: 4) }
        .not_to change(Transaction, :count)

      expect(response).to have_http_status(:ok)
      listing.reload
      txn = listing.sale_transactions.sole
      expect(txn).to be_sold
      expect(txn.quantity).to eq(4)
      # The hold ENDS with the sale it was for — 4 sold, nothing left held, and
      # the other 11 units are back on the open market for anybody.
      expect(listing.sold_units).to eq(4)
      expect(listing.available_units).to eq(11)
      expect(listing.held_units).to eq(0)
      expect(listing.available_units).to be >= listing.held_units
      expect(listing.status).to eq("active")
    end

    it "still retires the listing when the sale empties it" do
      listing = batch(quantity: 10)
      hold!(listing, units: 10)

      sell!(listing, buyer_id: buyer.id, quantity: 10)

      listing.reload
      expect(listing.status).to eq("sold")
      expect(listing.available_units).to eq(0)
      expect(listing.held_units).to eq(0)
      expect(listing.sale_transactions.sole).to be_sold
    end
  end

  # ── Trust counters: exactly once, in BOTH shapes ─────────────────────────────
  #
  # Transaction#bump_trust_counters! fires on the transition INTO `sold` and is
  # guarded by `saved_change_to_status?`. The close-out path now touches the row
  # twice (its quantity, then mark_sold!), so "exactly once" is the assertion
  # that would catch either failure: a quantity write that somehow bumped, or a
  # close-out that stopped bumping at all.
  describe "trust counters" do
    it "advancing a hold to sold bumps sold_count and bought_count by exactly 1" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)

      expect { sell!(listing, buyer_id: buyer.id, quantity: 10) }
        .to change { seller.reload.sold_count }.by(1)
        .and change { buyer.reload.bought_count }.by(1)

      expect(response).to have_http_status(:ok)
    end

    it "creating a fresh sold row (no hold at all) bumps each by exactly 1 too" do
      listing = batch(quantity: 15)

      expect { sell!(listing, buyer_id: buyer.id, quantity: 3) }
        .to change { seller.reload.sold_count }.by(1)
        .and change { buyer.reload.bought_count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(listing.sale_transactions.sole).to be_sold
    end

    it "does not bump anything twice when the held units are sold in two goes" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)

      # First sale closes the hold out (1 bump). The second is an ordinary new
      # sale on what is left (1 more) — two sales, two bumps, never three.
      expect do
        sell!(listing, buyer_id: buyer.id, quantity: 4)
        sell!(listing, buyer_id: buyer.id, quantity: 2)
      end.to change { seller.reload.sold_count }.by(2)
        .and change { buyer.reload.bought_count }.by(2)

      expect(listing.reload.sale_transactions.sold.count).to eq(2)
      expect(listing.held_units).to eq(0)
    end
  end

  # ── TASK-TX02's protection, unchanged ────────────────────────────────────────
  #
  # The close-out is now keyed on the BUYER rather than the listing's status, so
  # the thing TX02 was protecting has to be re-asserted at the new gate: a hold
  # for one person must never be quietly turned into somebody else's purchase.
  describe "a hold belonging to a DIFFERENT buyer" do
    it "is not closed out against a sale to someone else — the sale gets its own row" do
      listing = batch(quantity: 15, buyers: [ buyer, other ])
      hold!(listing, units: 10)
      hold_id = listing.open_transaction.id

      expect { sell!(listing, buyer_id: other.id, quantity: 2) }
        .to change(Transaction, :count).by(1)

      expect(response).to have_http_status(:ok)
      # The hold row is untouched: same buyer, same units, still open.
      hold = Transaction.find(hold_id)
      expect(hold).to be_reserved
      expect(hold.buyer_id).to eq(buyer.id)
      expect(hold.quantity).to eq(10)
      # And the sale is credited to the person the seller actually named.
      sale = listing.sale_transactions.sold.sole
      expect(sale.buyer_id).to eq(other.id)
      expect(sale.quantity).to eq(2)
      expect(other.reload.bought_count).to eq(1)
      expect(buyer.reload.bought_count).to eq(0)
      # Coherent: 2 sold of 15, 13 left, 10 of them still promised to `buyer`.
      listing.reload
      expect(listing.available_units).to eq(13)
      expect(listing.held_units).to eq(10)
      expect(listing.available_units).to be >= listing.held_units
    end

    it "is cancelled rather than re-attributed when the sale leaves nothing to hold" do
      # A SINGLE-item listing: it does flip to `reserved`, which is the shape the
      # old `reserved?` gate DID close out — and it closed it out against the
      # wrong buyer. Now the hold is cancelled instead: `buyer` never bought
      # anything, so `buyer` is never credited, and the sale is its own row.
      listing = create(:listing, :active, user: seller, quantity: 1)
      [ buyer, other ].each { |b| create(:conversation, listing: listing, buyer: b) }
      hold!(listing, for_buyer: buyer)
      expect(listing.status).to eq("reserved")
      hold_id = listing.open_transaction.id

      sell!(listing, buyer_id: other.id)

      expect(response).to have_http_status(:ok)
      expect(Transaction.exists?(hold_id)).to be(false)
      sale = listing.sale_transactions.sole
      expect(sale).to be_sold
      expect(sale.buyer_id).to eq(other.id)
      expect(buyer.reload.bought_count).to eq(0)
      expect(other.reload.bought_count).to eq(1)
      listing.reload
      expect(listing.status).to eq("sold")
      expect(listing.held_units).to eq(0)
      expect(listing.available_units).to eq(0)
    end
  end

  # ── The buyer-less paths, unchanged ─────────────────────────────────────────
  describe "a sale that names nobody" do
    it "bare legacy call: records its own buyer-less row and never closes out the hold" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)
      hold_id = listing.open_transaction.id

      expect { sell!(listing) }
        .to change { seller.reload.sold_count }.by(1)
        .and change(Transaction, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(Transaction.find(hold_id)).to be_reserved
      expect(buyer.reload.bought_count).to eq(0)
      sale = listing.sale_transactions.sold.sole
      expect(sale.buyer_id).to be_nil
      expect(sale.quantity).to eq(1) # a batch defaults to ONE unit
      listing.reload
      expect(listing.sold_units).to eq(1)
      expect(listing.available_units).to eq(14)
      expect(listing.held_units).to eq(10)
    end

    it "still closes out a genuinely RESERVED single-item listing using its own buyer (TASK-TX02)" do
      listing = create(:listing, :active, user: seller, quantity: 1)
      create(:conversation, listing: listing, buyer: buyer)
      hold!(listing, for_buyer: buyer)
      expect(listing.status).to eq("reserved")
      hold_id = listing.open_transaction.id

      expect { sell!(listing) }
        .to change { seller.reload.sold_count }.by(1)
        .and change { buyer.reload.bought_count }.by(1)
        .and change(Transaction, :count).by(0)

      txn = Transaction.find(hold_id)
      expect(txn).to be_sold
      expect(txn.buyer_id).to eq(buyer.id)
    end

    it "'Someone else / skip' (clear_buyer) still cancels the hold outright (SF-B3)" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)
      hold_id = listing.open_transaction.id

      # Net zero rows: the hold is destroyed AND the sale is written down.
      expect { sell!(listing, clear_buyer: true, quantity: 2) }
        .to change(Transaction, :count).by(0)
        .and change { seller.reload.sold_count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(Transaction.exists?(hold_id)).to be(false)
      expect(buyer.reload.bought_count).to eq(0)
      sale = listing.sale_transactions.sole
      expect(sale.buyer_id).to be_nil
      expect(sale.quantity).to eq(2)
      listing.reload
      expect(listing.held_units).to eq(0)
      expect(listing.available_units).to eq(13)
    end
  end

  # ── SF-B8's floor no longer reads a phantom hold ─────────────────────────────
  describe "the SF-B8 quantity floor" do
    it "lets a down-edit through once the held units have been sold to the holder" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)
      sell!(listing, buyer_id: buyer.id, quantity: 3)
      listing.reload
      expect(listing.held_units).to eq(0)
      expect(listing.sold_units).to eq(3)

      # Before SF-B9 this was a 422 with code `quantity_below_held_units`: the
      # phantom 10-unit hold set the floor, so the seller could not lower a
      # listing they had already finished selling out of.
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 6 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(6)
      expect(listing.available_units).to eq(3)
      expect(listing.held_units).to eq(0)
    end

    it "still refuses the same edit while the hold is genuinely open (SF-B8 intact)" do
      listing = batch(quantity: 15)
      hold!(listing, units: 10)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 6 } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)
      listing.reload
      expect(listing.quantity).to eq(15)
      expect(listing.held_units).to eq(10)
    end
  end

  # ── The invariant, not just this instance ────────────────────────────────────
  #
  # `available_units < held_units` is the CLASS of bug SF-B9 belongs to: SF-B8
  # closed the quantity-edit route to it, this ticket closed the ordinary-sale
  # route, and holds are advisory (never subtracted from `available_units`), so
  # any sale can in principle sell units a hold was still claiming. Asserted over
  # every way a sale can be recorded rather than only the one that was reported,
  # so the next route in is a failing spec rather than another buyer's screen.
  describe "invariant: available_units >= held_units after any sale path" do
    [
      { name: "the whole hold, to the buyer holding it",     params: { quantity: 10, to: :buyer } },
      { name: "part of the hold, to the buyer holding it",   params: { quantity: 4,  to: :buyer } },
      { name: "more units than are left over after the hold", params: { quantity: 12, to: :other } },
      { name: "everything, to a different buyer",            params: { quantity: 15, to: :other } },
      { name: "with no buyer named at all (legacy client)",  params: { quantity: 12, to: nil } },
      { name: "to someone not on Hatiwal",                   params: { quantity: 12, to: :clear } }
    ].each do |shape|
      it "holds after a sale of #{shape[:name]}" do
        listing = batch(quantity: 15, buyers: [ buyer, other ])
        hold!(listing, units: 10)

        sale_params = { quantity: shape[:params][:quantity] }
        case shape[:params][:to]
        when :buyer then sale_params[:buyer_id]   = buyer.id
        when :other then sale_params[:buyer_id]   = other.id
        when :clear then sale_params[:clear_buyer] = true
        end

        sell!(listing, **sale_params)

        expect(response).to have_http_status(:ok)
        listing.reload
        expect(listing.available_units).to be >= listing.held_units,
          "available_units (#{listing.available_units}) is below held_units " \
          "(#{listing.held_units}) — a buyer would be shown more units held than exist"
        # And the ledger never claims more units than the listing has.
        expect(listing.sale_transactions.sold.sum(:quantity)).to eq(listing.sold_units)
        expect(listing.sold_units).to be <= listing.quantity
      end
    end

    it "narrows a surviving hold to the stock the sale left behind rather than refusing the sale" do
      # The sale is a fact that already happened in person, so it is recorded and
      # the ADVISORY hold gives way — the opposite call to SF-B8, where a seller
      # editing `quantity` is refused because an edit is a choice they can revise.
      listing = batch(quantity: 15, buyers: [ buyer, other ])
      hold!(listing, units: 10)
      hold_id = listing.open_transaction.id

      sell!(listing, buyer_id: other.id, quantity: 12)

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.available_units).to eq(3)
      expect(listing.held_units).to eq(3)
      hold = Transaction.find(hold_id)
      expect(hold).to be_reserved
      expect(hold.buyer_id).to eq(buyer.id) # still theirs, just smaller
      expect(hold.quantity).to eq(3)
    end

    # Measured, not imagined: with a plain `update!` here the whole sale came back
    # 422 "Buyer must be a participant in a conversation on this listing" and
    # rolled back — a rule about a THIRD party's deleted chat thread blocking a
    # seller from recording a sale to somebody else.
    context "when the holder's chat thread has been deleted by both parties" do
      def hold_with_deleted_thread(quantity:, held:)
        listing = batch(quantity: quantity, buyers: [ buyer, other ])
        hold!(listing, units: held)
        # Conversation#delete_for! hard-destroys the row once BOTH sides delete
        # it, and Transaction validates that its buyer is a participant — so the
        # hold can no longer be saved through validations at all.
        Conversation.find_by(listing_id: listing.id, buyer_id: buyer.id).destroy!
        listing
      end

      it "still records the sale and still narrows the hold" do
        listing = hold_with_deleted_thread(quantity: 15, held: 10)
        hold_id = listing.open_transaction.id

        sell!(listing, buyer_id: other.id, quantity: 12)

        expect(response).to have_http_status(:ok)
        listing.reload
        expect(listing.sold_units).to eq(12)
        expect(listing.available_units).to eq(3)
        expect(Transaction.find(hold_id).quantity).to eq(3)
        expect(listing.held_units).to eq(3)
      end

      it "still records the sale and still destroys the hold when nothing is left" do
        listing = hold_with_deleted_thread(quantity: 15, held: 10)
        hold_id = listing.open_transaction.id

        sell!(listing, buyer_id: other.id, quantity: 15)

        expect(response).to have_http_status(:ok)
        expect(Transaction.exists?(hold_id)).to be(false)
        listing.reload
        expect(listing.status).to eq("sold")
        expect(listing.held_units).to eq(0)
      end
    end

    it "destroys a surviving hold when the sale leaves nothing at all" do
      listing = batch(quantity: 15, buyers: [ buyer, other ])
      hold!(listing, units: 10)
      hold_id = listing.open_transaction.id

      sell!(listing, buyer_id: other.id, quantity: 15)

      expect(response).to have_http_status(:ok)
      expect(Transaction.exists?(hold_id)).to be(false)
      listing.reload
      expect(listing.status).to eq("sold")
      expect(listing.held_units).to eq(0)
      expect(listing.available_units).to eq(0)
      # Cancelling a still-RESERVED row never took a trust counter, so there is
      # nothing to give back (Transaction#void! reasons the same way).
      expect(buyer.reload.bought_count).to eq(0)
      expect(other.reload.bought_count).to eq(1)
    end
  end
end
