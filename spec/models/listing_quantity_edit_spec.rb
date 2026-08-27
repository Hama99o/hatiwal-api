require "rails_helper"

# SF-B6 — editing a listing's `quantity` must reconcile the listing's status.
#
# The owner-reported bug: a seller with 15 of 15 sold raised the quantity to 20
# and the listing stayed `sold`. Five units were then stranded — out of
# `browsable`, so no buyer could see them, AND out of `ListingPolicy#sold?`
# (which needs `live?`), so the seller could not sell them either. There was no
# in-app recovery at all.
#
# The mirror image was broken too: dropping the quantity onto `sold_units` left a
# live listing with nothing left to sell, and dropping it BELOW `sold_units` hit
# the DB CHECK constraint and came back as a 500 with an empty body.
#
# The status arithmetic itself is SF-B4's `reconcile_sold_status!`, reused —
# these specs pin the wiring (which edits trigger it, and what must NOT).
RSpec.describe Listing, "quantity edits (SF-B6)" do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }

  # A sold-out listing, straight from the columns — the state the owner's device
  # was in. No ledger needed for the status arithmetic; the end-to-end case with
  # a real Transaction is covered separately below.
  def sold_out(total:, expires_at: nil)
    create(:listing, :sold, user: seller, quantity: total, sold_units: total, expires_at: expires_at)
  end

  describe "raising the quantity of a sold-out listing — the headline fix" do
    it "re-opens it as active and clears the sale date" do
      listing = sold_out(total: 15)

      expect(listing.update(quantity: 20)).to be(true)

      expect(listing.reload.status).to eq("active")
      expect(listing.sold_at).to be_nil
    end

    it "genuinely comes back: browsable, sellable, and with the right stock" do
      listing = sold_out(total: 15)

      listing.update!(quantity: 20)
      listing.reload

      expect(Listing.browsable).to include(listing)
      expect(ListingPolicy.new(seller, listing).sold?).to be(true)
      expect(listing.available_units).to eq(5)
    end

    it "does the same for a sale recorded through the real ledger" do
      listing = create(:listing, :active, user: seller, quantity: 15, price: 1000)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 15)
      listing.record_units_sold!(15)
      listing.sold!
      expect(listing.reload.status).to eq("sold")

      listing.update!(quantity: 20)

      expect(listing.reload.status).to eq("active")
      expect(listing.available_units).to eq(5)
      # The ledger is untouched — the sale still happened.
      expect(listing.sale_transactions.sold.sum(:quantity)).to eq(15)
      expect(listing.sold_units).to eq(15)
    end
  end

  describe "setting the quantity to exactly what is already sold" do
    it "leaves a sold-out listing sold — there is nothing to re-open" do
      listing = sold_out(total: 15)

      expect(listing.update(quantity: 15)).to be(true)

      expect(listing.reload.status).to eq("sold")
    end

    it "retires it again when the seller undoes the raise" do
      listing = sold_out(total: 15)
      listing.update!(quantity: 20)
      expect(listing.reload.status).to eq("active")

      listing.update!(quantity: 15)

      expect(listing.reload.status).to eq("sold")
      expect(listing.sold_at).to be_present
      expect(Listing.browsable).not_to include(listing)
    end
  end

  describe "lowering the quantity onto the units already sold" do
    it "flips a live listing to sold" do
      listing = create(:listing, :active, user: seller, quantity: 20, sold_units: 15)

      expect(listing.update(quantity: 15)).to be(true)

      expect(listing.reload.status).to eq("sold")
      expect(listing.available_units).to eq(0)
      expect(listing.sold_at).to be_present
    end
  end

  describe "lowering the quantity BELOW the units already sold" do
    it "is refused as a plain validation error on :quantity — never a CheckViolation" do
      listing = sold_out(total: 15)

      expect { listing.update(quantity: 10) }.not_to raise_error
      expect(listing.update(quantity: 10)).to be(false)
      expect(listing.errors[:quantity].join).to include("already sold")
      expect(listing.reload.quantity).to eq(15)
    end

    it "raises RecordInvalid, never the DB's CheckViolation, on the bang form" do
      listing = sold_out(total: 15)

      raised = begin
        listing.update!(quantity: 10)
        nil
      rescue StandardError => e
        e
      end

      expect(raised).to be_a(ActiveRecord::RecordInvalid)
      # ActiveRecord::CheckViolation is a StatementInvalid — the class of failure
      # that reaches the seller as a 500 with an empty body.
      expect(raised).not_to be_a(ActiveRecord::StatementInvalid)
    end

    it "names the units already sold and the way out (SF-B4's undo)" do
      listing = sold_out(total: 15)
      listing.update(quantity: 10)

      expect(listing.errors.full_messages.first).to eq(
        "Quantity cannot be less than the 15 units already sold. " \
        "Set it to 15 or more, or undo a sale first."
      )
    end

    it "carries the machine-readable code the ps/fa clients localize" do
      listing = sold_out(total: 15)
      listing.update(quantity: 10)

      expect(listing.error_code).to eq(Listing::QUANTITY_BELOW_SOLD_UNITS_CODE)
      expect(listing.error_code).to eq("quantity_below_sold_units")
    end

    it "singularizes for a one-unit sale" do
      listing = create(:listing, :active, user: seller, quantity: 5, sold_units: 1)
      listing.update(quantity: 0)
      # quantity 0 also trips the >0 numericality rule; the sold-units sentence
      # must still be the one that names the already-sold count.
      expect(listing.errors[:quantity].join).to include("the 1 unit already sold")
    end

    it "reports no error code for an unrelated validation failure" do
      listing = create(:listing, :active, user: seller)
      listing.update(title: "")

      expect(listing).not_to be_valid
      expect(listing.error_code).to be_nil
    end

    it "keeps the DB CHECK constraint as the backstop" do
      listing = sold_out(total: 15)

      expect { listing.update_column(:quantity, 10) }
        .to raise_error(ActiveRecord::StatementInvalid, /listings_sold_units_within_quantity/)
    end
  end

  describe "expiry on re-open" do
    it "refreshes an expiry that has already passed, so it does not land in the Expired tab" do
      listing = sold_out(total: 15, expires_at: 3.days.ago)

      listing.update!(quantity: 20)
      listing.reload

      expect(listing.expires_at).to be_within(1.minute).of(Listing::LISTING_LIFESPAN.from_now)
      expect(listing).not_to be_expired
      expect(Listing.expired_active).not_to include(listing)
      expect(Listing.browsable).to include(listing)
    end

    it "leaves an expiry that is still in the future alone" do
      original = 10.days.from_now
      listing = sold_out(total: 15, expires_at: original)

      listing.update!(quantity: 20)

      expect(listing.reload.expires_at).to be_within(1.second).of(original)
    end

    it "does not invent an expiry for a listing that never had one" do
      listing = sold_out(total: 15, expires_at: nil)

      listing.update!(quantity: 20)

      expect(listing.reload.expires_at).to be_nil
      expect(Listing.browsable).to include(listing)
    end

    # The same hole existed on the SF-B4 correction path: undoing a sale on a
    # sold-out listing that had since expired re-opened it straight into Expired.
    it "also refreshes when a sale CORRECTION re-opens the listing" do
      listing = create(:listing, :active, user: seller, quantity: 5, price: 1000)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 5)
      listing.record_units_sold!(5)
      listing.sold!
      listing.update_columns(expires_at: 2.days.ago)

      listing.correct_sold_transaction!(transaction: txn, quantity: 2)

      expect(listing.reload.status).to eq("active")
      expect(listing.expires_at).to be_within(1.minute).of(Listing::LISTING_LIFESPAN.from_now)
      expect(Listing.browsable).to include(listing)
    end
  end

  describe "everything else must be completely unaffected" do
    it "leaves a sold listing sold when only the title is edited" do
      listing = sold_out(total: 15)
      was_sold_at = listing.sold_at

      listing.update!(title: "Same bags, better photo")

      expect(listing.reload.status).to eq("sold")
      expect(listing.sold_at).to be_within(1.second).of(was_sold_at)
    end

    it "leaves a single-item sold listing sold when only the price is edited" do
      listing = create(:listing, :sold, user: seller, quantity: 1, sold_units: 1)

      listing.update!(price: 500)

      expect(listing.reload.status).to eq("sold")
    end

    it "keeps a single-item active listing active when its quantity is raised" do
      listing = create(:listing, :active, user: seller, quantity: 1)

      listing.update!(quantity: 4)

      expect(listing.reload.status).to eq("active")
      expect(listing.available_units).to eq(4)
    end

    it "never retires a listing whose stock is merely partly sold" do
      listing = create(:listing, :active, user: seller, quantity: 20, sold_units: 15)

      listing.update!(quantity: 16)

      expect(listing.reload.status).to eq("active")
      expect(Listing.browsable).to include(listing)
    end

    it "does not touch a draft listing's status" do
      listing = create(:listing, user: seller, quantity: 5)

      listing.update!(quantity: 9)

      expect(listing.reload.status).to eq("draft")
    end

    # The reason the reconcile callback is registered AFTER record_price_history:
    # its nested `update!` replaces `saved_changes`, so running first would hide
    # the price change from the history recorder.
    it "still records price history when price and quantity change in one edit" do
      listing = sold_out(total: 15)
      listing.update!(price: 900)
      expect(listing.price_histories.count).to eq(1)

      listing.update!(price: 700, quantity: 20)

      expect(listing.reload.price_histories.count).to eq(2)
      expect(listing.status).to eq("active")
    end
  end
end
