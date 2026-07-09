require "rails_helper"

RSpec.describe ReviewPolicy, type: :policy do
  let(:sale)    { create(:transaction, :sold) }
  let(:seller)  { sale.seller }
  let(:buyer)   { sale.buyer }
  let(:outsider) { create(:user) }

  describe "#create?" do
    it "allows a party to a sold sale" do
      review = Review.new(sale: sale, reviewer: seller)
      expect(described_class.new(seller, review).create?).to be(true)
    end

    it "denies a non-party" do
      review = Review.new(sale: sale, reviewer: outsider)
      expect(described_class.new(outsider, review).create?).to be(false)
    end

    it "denies when the sale is not sold" do
      reserved = create(:transaction)
      review = Review.new(sale: reserved, reviewer: reserved.seller)
      expect(described_class.new(reserved.seller, review).create?).to be(false)
    end
  end

  describe "#update?" do
    it "allows the author while the review is hidden" do
      review = create(:review, sale: sale, reviewer: seller, reviewee: buyer, role: :of_buyer)
      expect(described_class.new(seller, review).update?).to be(true)
    end

    it "denies once the review is visible (locked)" do
      review = create(:review, :visible, sale: sale, reviewer: seller, reviewee: buyer, role: :of_buyer)
      expect(described_class.new(seller, review).update?).to be(false)
    end

    it "denies a non-author" do
      review = create(:review, sale: sale, reviewer: seller, reviewee: buyer, role: :of_buyer)
      expect(described_class.new(buyer, review).update?).to be(false)
    end
  end

  describe "#pending?" do
    it "requires a user" do
      expect(described_class.new(seller, :review).pending?).to be(true)
      expect(described_class.new(nil, :review).pending?).to be(false)
    end
  end
end
