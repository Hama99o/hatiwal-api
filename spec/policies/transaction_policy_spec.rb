require "rails_helper"

RSpec.describe TransactionPolicy do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:stranger) { create(:user) }
  let(:txn) { create(:transaction, seller: seller, buyer: buyer) }

  describe "#index?" do
    it "is true for any authenticated user" do
      expect(described_class.new(stranger, Transaction).index?).to be true
    end
  end

  describe "#show?" do
    it "is true for the seller" do
      expect(described_class.new(seller, txn).show?).to be true
    end

    it "is true for the buyer" do
      expect(described_class.new(buyer, txn).show?).to be true
    end

    it "is false for an unrelated user" do
      expect(described_class.new(stranger, txn).show?).to be false
    end

    it "is false for a guest" do
      expect(described_class.new(nil, txn).show?).to be false
    end
  end

  # SF-B4 — correcting/voiding a recorded sale is the seller's own act, on their
  # own ledger row, and only once that row is actually a sale.
  describe "#update? / #destroy?" do
    let(:sold_txn) { create(:transaction, :sold, seller: seller, buyer: buyer) }

    it "is true for the seller of a sold transaction" do
      policy = described_class.new(seller, sold_txn)
      expect(policy.update?).to be true
      expect(policy.destroy?).to be true
    end

    it "is false for the BUYER — they must never edit the other side's ledger" do
      policy = described_class.new(buyer, sold_txn)
      expect(policy.update?).to be false
      expect(policy.destroy?).to be false
    end

    it "is false for an unrelated user and for a guest" do
      expect(described_class.new(stranger, sold_txn).update?).to be false
      expect(described_class.new(nil, sold_txn).update?).to be false
    end

    # Releasing a hold is PUT /my/listings/:id/activate, which already cancels
    # the open transaction. Two doors to the same room would drift apart.
    it "is false on a still-RESERVED transaction, even for the seller" do
      policy = described_class.new(seller, txn)
      expect(txn).to be_reserved
      expect(policy.update?).to be false
      expect(policy.destroy?).to be false
    end
  end

  describe "Scope" do
    it "returns only the caller's own transactions (as buyer or seller)" do
      mine = txn
      create(:transaction) # unrelated

      resolved = TransactionPolicy::Scope.new(seller, Transaction).resolve
      expect(resolved).to contain_exactly(mine)
    end

    it "returns none for a guest" do
      create(:transaction)
      resolved = TransactionPolicy::Scope.new(nil, Transaction).resolve
      expect(resolved).to be_empty
    end
  end

  # Review 2026-10-08: the sale belongs to the shop it was MADE in (the pinned
  # transactions.shop_id), not to wherever its listing lives now.
  describe "a shop sale after its listing moved" do
    let(:owner) { create(:user) }
    let(:shop_a) { create(:shop, owner: owner) }
    let(:shop_b) { create(:shop, owner: owner) }
    let(:member_a) { create(:user) }
    let(:member_b) { create(:user) }
    let(:listing) { create(:listing, :active, user: owner, shop: shop_a, quantity: 3) }
    let(:sale) { create(:transaction, :outside_buyer, seller: owner, listing: listing) }

    before do
      shop_a.shop_members.create!(user: member_a, role: :staff)
      shop_b.shop_members.create!(user: member_b, role: :staff)
      sale
      listing.update_columns(shop_id: shop_b.id)
    end

    it "the sale's own shop team still manages it; the new shop's team does not" do
      expect(sale.reload.shop_id).to eq(shop_a.id)
      expect(described_class.new(member_a, sale).update?).to be true
      expect(described_class.new(member_b, sale).update?).to be false
      expect(described_class.new(member_b, sale).show?).to be false
    end
  end
end
