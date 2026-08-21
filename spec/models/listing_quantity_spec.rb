require "rails_helper"

# Multi-quantity listings — Tier 1 of docs/SPIKE_LISTING_QUANTITY.md.
#
# The feature exists because a seller with 15 identical bags could not say so,
# and a buyer who wanted 15 assumed there was one and never asked.
#
# The invariant everything else depends on: a listing that still has stock stays
# `active` and browsable. Retiring it early is the failure that would have made
# this feature break the feed.
RSpec.describe Listing, "multi-quantity" do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:other_buyer) { create(:user) }

  # A Transaction validates that the buyer has a conversation on the listing
  # (Transaction#buyer_is_conversation_participant) — a deliberate guard so a
  # seller cannot name an arbitrary stranger as their buyer. Any test that records
  # a sale therefore has to give the buyer a conversation first, exactly as the
  # real buyer-picker flow does (it only offers conversation participants).
  def with_conversation(listing, a_buyer)
    create(:conversation, listing: listing, buyer: a_buyer)
    listing
  end

  describe "defaults — the single-unit case must be untouched" do
    it "is a 1-unit listing unless the seller says otherwise" do
      listing = create(:listing, user: seller)
      expect(listing.quantity).to eq(1)
      expect(listing.sold_units).to eq(0)
      expect(listing.available_units).to eq(1)
      expect(listing).not_to be_multi_unit
    end

    it "records quantity 1 on a transaction by default" do
      listing = with_conversation(create(:listing, user: seller, status: :active), buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id)
      expect(txn.quantity).to eq(1)
    end
  end

  describe "available_units" do
    it "is the remainder" do
      listing = create(:listing, user: seller, quantity: 15, sold_units: 4)
      expect(listing.available_units).to eq(11)
    end

    it "never goes negative even if the data is somehow inconsistent" do
      listing = build(:listing, user: seller, quantity: 5, sold_units: 9)
      expect(listing.available_units).to eq(0)
    end
  end

  describe "#record_units_sold!" do
    it "returns false while stock remains, so the caller keeps the listing active" do
      listing = create(:listing, user: seller, status: :active, quantity: 15)
      expect(listing.record_units_sold!(3)).to be(false)
      expect(listing.reload.sold_units).to eq(3)
      expect(listing.available_units).to eq(12)
    end

    it "returns true on the sale that empties it, so the caller retires it" do
      listing = create(:listing, user: seller, status: :active, quantity: 3)
      expect(listing.record_units_sold!(3)).to be(true)
      expect(listing.reload.available_units).to eq(0)
    end

    it "clamps instead of overselling — the sale happened, the ledger must not lose it" do
      listing = create(:listing, user: seller, status: :active, quantity: 2)
      expect(listing.record_units_sold!(5)).to be(true)
      expect(listing.reload.sold_units).to eq(2)
    end

    it "is a no-op once the stock is gone" do
      listing = create(:listing, user: seller, status: :active, quantity: 1, sold_units: 1)
      expect(listing.record_units_sold!(1)).to be(false)
      expect(listing.reload.sold_units).to eq(1)
    end

    it "rejects a non-positive count" do
      listing = create(:listing, user: seller, quantity: 5)
      expect { listing.record_units_sold!(0) }.to raise_error(ArgumentError)
    end
  end

  describe "the database refuses to oversell, whatever the app does" do
    # The app clamps, but the app is the thing that gets edited. This is the
    # guarantee that survives a future bug: two buyers must never be promised
    # the same units and sent to the same meetup.
    it "rejects sold_units above quantity at the DB level" do
      listing = create(:listing, user: seller, quantity: 3)
      expect {
        listing.update_column(:sold_units, 4)
      }.to raise_error(ActiveRecord::StatementInvalid, /listings_sold_units_within_quantity/)
    end

    it "rejects a zero quantity at the DB level" do
      listing = create(:listing, user: seller)
      expect {
        listing.update_column(:quantity, 0)
      }.to raise_error(ActiveRecord::StatementInvalid, /listings_quantity_positive/)
    end
  end

  describe "validations" do
    it "rejects a quantity below 1" do
      expect(build(:listing, user: seller, quantity: 0)).not_to be_valid
    end

    it "rejects an implausible quantity" do
      expect(build(:listing, user: seller, quantity: 1000)).not_to be_valid
    end

    it "accepts the 999 ceiling" do
      expect(build(:listing, user: seller, quantity: 999)).to be_valid
    end
  end

  describe "#sold_with_buyer! with quantity" do
    it "defaults to the whole remaining stock — 'I sold them' needs no number" do
      listing = with_conversation(create(:listing, user: seller, status: :active, quantity: 15), buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id)
      expect(txn.quantity).to eq(15)
    end

    it "records a partial sale for one buyer" do
      listing = with_conversation(create(:listing, user: seller, status: :active, quantity: 15), buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 3)
      expect(txn.quantity).to eq(3)
    end

    it "keeps ONE transaction per buyer, so 3 units is one deal and one review" do
      listing = with_conversation(create(:listing, user: seller, status: :active, quantity: 15), buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 3)
      expect(listing.sale_transactions.count).to eq(1)
      expect(txn.buyer_id).to eq(buyer.id)
    end

    it "records a second buyer as its own sale — the 'who bought how many' ledger" do
      listing = with_conversation(create(:listing, user: seller, status: :active, quantity: 15), buyer)
      create(:conversation, listing: listing, buyer: other_buyer)
      listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 3)
      listing.record_units_sold!(3)
      listing.sold_with_buyer!(buyer_id: other_buyer.id, quantity: 5)

      sales = listing.sale_transactions.reload
      expect(sales.count).to eq(2)
      expect(sales.map(&:quantity)).to contain_exactly(3, 5)
      expect(sales.map(&:buyer_id)).to contain_exactly(buyer.id, other_buyer.id)
    end

    it "cannot be talked into overselling by a stale client" do
      listing = with_conversation(create(:listing, user: seller, status: :active, quantity: 2), buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 99)
      expect(txn.quantity).to eq(2)
    end
  end

  describe "the feed invariant" do
    it "keeps a partially-sold listing browsable — the line that would have broken it" do
      listing = create(:listing, user: seller, status: :active, quantity: 15)
      listing.record_units_sold!(4)
      expect(Listing.browsable).to include(listing.reload)
      expect(listing.status).to eq("active")
    end
  end
end
