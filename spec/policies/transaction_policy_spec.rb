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
