require "rails_helper"

# SF-B4 at the model layer — Transaction#correct! / #void! and the listing-level
# orchestration that keeps `listings.sold_units` and the listing's status in step
# with the ledger.
#
# The request specs (spec/requests/api/v1/my/transaction_corrections_spec.rb)
# cover the endpoint contract; this file covers the arithmetic and the invariants
# a controller cannot see: the locks, the counter floors, and the fact that
# nothing here can ever leave `sold_units` outside its DB check constraint.
RSpec.describe "Sale corrections (SF-B4)", type: :model do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:buyer2) { create(:user) }

  def sold_sale(total:, units:, to: nil)
    listing = create(:listing, :active, user: seller, quantity: total, price: 1000)
    [ to, buyer, buyer2 ].compact.uniq.each do |b|
      create(:conversation, listing: listing, seller: seller, buyer: b)
    end
    txn = listing.sold_with_buyer!(buyer_id: to&.id, quantity: units)
    listing.record_units_sold!(units)
    listing.sold! if listing.reload.available_units.zero?
    [ listing.reload, txn.reload ]
  end

  describe "Listing#correct_sold_transaction!" do
    it "refuses a transaction belonging to a different listing" do
      _l1, txn = sold_sale(total: 1, units: 1, to: buyer)
      other = create(:listing, :active, user: seller)

      expect { other.correct_sold_transaction!(transaction: txn, quantity: 1) }
        .to raise_error(ArgumentError, /does not belong/)
    end

    it "refuses a still-reserved transaction" do
      listing = create(:listing, :active, user: seller, quantity: 5)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      hold = listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 2)

      expect { listing.correct_sold_transaction!(transaction: hold, quantity: 1) }
        .to raise_error(ArgumentError, /only a sold transaction/)
    end

    it "does not confuse the requested quantity with the listing's own quantity" do
      # The trap the keyword argument sets: `quantity` inside the method shadows
      # the column reader. If the status reconciliation read the seller's number
      # instead of the listing's total, a 1-unit correction on a 5-unit listing
      # would satisfy `new_sold_units >= quantity` and wrongly retire it.
      listing, txn = sold_sale(total: 5, units: 5, to: buyer)

      listing.correct_sold_transaction!(transaction: txn, quantity: 1)

      expect(listing.reload.status).to eq("active")
      expect(listing.quantity).to eq(5)
      expect(listing.sold_units).to eq(1)
    end

    it "leaves a single-item listing sold when its one sale is merely re-priced" do
      listing, txn = sold_sale(total: 1, units: 1, to: buyer)

      listing.correct_sold_transaction!(transaction: txn, final_price: 250)

      expect(listing.reload.status).to eq("sold")
      expect(listing.sold_units).to eq(1)
      expect(txn.reload.final_price).to eq(250)
    end

    it "keeps sold_units inside the DB check constraint on every path" do
      listing, txn = sold_sale(total: 4, units: 4, to: buyer)

      [ 1, 3, 4, 2 ].each do |n|
        listing.correct_sold_transaction!(transaction: txn, quantity: n)
        listing.reload
        expect(listing.sold_units).to eq(n)
        expect(listing.sold_units).to be_between(0, listing.quantity)
      end
    end

    it "returns the reloaded listing so the caller sees the reconciled status" do
      listing, txn = sold_sale(total: 5, units: 5, to: buyer)

      result = listing.correct_sold_transaction!(transaction: txn, quantity: 2)

      expect(result).to eq(listing)
      expect(result.status).to eq("active")
      expect(result.sold_units).to eq(2)
    end
  end

  describe "Transaction#void!" do
    it "decrements both counters with a zero floor" do
      _listing, txn = sold_sale(total: 1, units: 1, to: buyer)
      seller.update_columns(sold_count: 0)
      buyer.update_columns(bought_count: 0)

      txn.void!

      expect(seller.reload.sold_count).to eq(0)
      expect(buyer.reload.bought_count).to eq(0)
    end

    it "decrements only the seller's counter for a buyer-less sale" do
      listing = create(:listing, :active, user: seller)
      txn = listing.sold_with_buyer!(buyer_id: nil, clear_buyer: true)
      expect(seller.reload.sold_count).to eq(1)

      txn.void!

      expect(seller.reload.sold_count).to eq(0)
    end

    # A reserved row never bumped a counter, so voiding one must not give
    # anything back — otherwise releasing a hold would silently erase a real,
    # unrelated sale from the seller's trust stat.
    it "touches no counter when the row was only reserved" do
      listing = create(:listing, :active, user: seller, quantity: 5)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      hold = listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 2)
      seller.update_columns(sold_count: 3)

      hold.void!

      expect(seller.reload.sold_count).to eq(3)
      expect(Transaction.exists?(hold.id)).to be(false)
    end

    it "raises CorrectionBlocked and destroys nothing when a review is attached" do
      _listing, txn = sold_sale(total: 1, units: 1, to: buyer)
      create(:review, sale: txn, reviewer: seller, reviewee: buyer, role: :of_buyer)

      expect { txn.void! }.to raise_error(Listing::CorrectionBlocked)
      expect(Transaction.exists?(txn.id)).to be(true)
      expect(seller.reload.sold_count).to eq(1)
    end
  end

  describe "Transaction#correct!" do
    it "moves bought_count when the buyer changes" do
      _listing, txn = sold_sale(total: 1, units: 1, to: buyer)

      txn.correct!(buyer_id: buyer2.id)

      expect(buyer.reload.bought_count).to eq(0)
      expect(buyer2.reload.bought_count).to eq(1)
    end

    it "does not touch bought_count when the buyer is unchanged" do
      _listing, txn = sold_sale(total: 5, units: 3, to: buyer)

      expect { txn.correct!(quantity: 2) }.not_to change { buyer.reload.bought_count }
    end

    it "treats re-passing the SAME buyer_id as no change" do
      _listing, txn = sold_sale(total: 1, units: 1, to: buyer)

      expect { txn.correct!(buyer_id: buyer.id) }.not_to change { buyer.reload.bought_count }
    end

    it "credits a buyer when an outside-buyer sale is later attributed to an account" do
      listing = create(:listing, :active, user: seller)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      txn = listing.sold_with_buyer!(buyer_id: nil, clear_buyer: true)

      txn.correct!(buyer_id: buyer.id)

      expect(txn.reload.buyer_id).to eq(buyer.id)
      expect(buyer.reload.bought_count).to eq(1)
    end

    it "releases the buyer's count when the sale is reassigned to nobody" do
      _listing, txn = sold_sale(total: 1, units: 1, to: buyer)

      txn.correct!(clear_buyer: true)

      expect(txn.reload.buyer_id).to be_nil
      expect(buyer.reload.bought_count).to eq(0)
    end

    it "never re-bumps the seller's sold_count — the status did not change" do
      _listing, txn = sold_sale(total: 5, units: 3, to: buyer)

      expect { txn.correct!(quantity: 1, final_price: 10) }
        .not_to change { seller.reload.sold_count }
    end

    it "allows a quantity/price edit on a reviewed sale but refuses a buyer change" do
      _listing, txn = sold_sale(total: 5, units: 3, to: buyer)
      create(:review, sale: txn, reviewer: seller, reviewee: buyer, role: :of_buyer)

      expect { txn.correct!(quantity: 2, final_price: 500) }.not_to raise_error
      expect(txn.reload.quantity).to eq(2)

      expect { txn.correct!(buyer_id: buyer2.id) }.to raise_error(Listing::CorrectionBlocked)
      expect(txn.reload.buyer_id).to eq(buyer.id)
    end
  end
end
