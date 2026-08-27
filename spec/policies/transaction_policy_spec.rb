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
end
