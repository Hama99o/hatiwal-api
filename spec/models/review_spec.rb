require "rails_helper"

RSpec.describe Review, type: :model do
  describe "associations" do
    it { should belong_to(:sale).class_name("Transaction").with_foreign_key(:transaction_id) }
    it { should belong_to(:reviewer).class_name("User") }
    it { should belong_to(:reviewee).class_name("User") }
  end

  describe "validations" do
    subject { build(:review) }

    it { should validate_presence_of(:rating) }
    it { should validate_numericality_of(:rating).only_integer.is_greater_than_or_equal_to(1).is_less_than_or_equal_to(5) }

    it "is valid for the seller reviewing the buyer" do
      expect(build(:review)).to be_valid
    end

    it "is valid for the buyer reviewing the seller" do
      expect(build(:review, :of_seller)).to be_valid
    end

    it "rejects a second review from the same reviewer on the same sale" do
      first = create(:review)
      dup = build(:review, sale: first.sale, reviewer: first.reviewer, reviewee: first.reviewee, role: first.role)
      expect(dup).not_to be_valid
      expect(dup.errors[:reviewer_id]).to be_present
    end

    it "rejects a review on a sale that is not sold" do
      reserved = create(:transaction) # default status: reserved
      review = build(:review, sale: reserved, reviewer: reserved.seller, reviewee: reserved.buyer, role: :of_buyer)
      expect(review).not_to be_valid
      expect(review.errors[:base]).to include("can only review a completed sale")
    end

    it "rejects a reviewer who is not a party to the sale" do
      sale = create(:transaction, :sold)
      outsider = create(:user)
      review = build(:review, sale: sale, reviewer: outsider, reviewee: sale.buyer, role: :of_buyer)
      expect(review).not_to be_valid
      expect(review.errors[:reviewer_id]).to be_present
    end

    it "rejects a role that does not match the reviewee's side" do
      sale = create(:transaction, :sold)
      review = build(:review, sale: sale, reviewer: sale.seller, reviewee: sale.buyer, role: :of_seller)
      expect(review).not_to be_valid
      expect(review.errors[:role]).to be_present
    end
  end

  describe "#submit!" do
    let(:sale) { create(:transaction, :sold) }

    it "stays hidden when only one party has reviewed" do
      review = build(:review, sale: sale, reviewer: sale.seller, reviewee: sale.buyer, role: :of_buyer)
      review.submit!
      expect(review.reload.visible).to be(false)
      expect(sale.buyer.reload.review_count).to eq(0)
    end

    it "reveals BOTH reviews once the second party submits" do
      seller_review = build(:review, sale: sale, reviewer: sale.seller, reviewee: sale.buyer, role: :of_buyer, rating: 4)
      seller_review.submit!
      buyer_review = build(:review, sale: sale, reviewer: sale.buyer, reviewee: sale.seller, role: :of_seller, rating: 5)
      buyer_review.submit!

      expect(seller_review.reload.visible).to be(true)
      expect(buyer_review.reload.visible).to be(true)
      expect(seller_review.revealed_at).to be_present
    end

    it "recomputes the reviewee aggregates on reveal" do
      build(:review, sale: sale, reviewer: sale.seller, reviewee: sale.buyer, role: :of_buyer, rating: 4).submit!
      build(:review, sale: sale, reviewer: sale.buyer, reviewee: sale.seller, role: :of_seller, rating: 2).submit!

      expect(sale.buyer.reload.review_count).to eq(1)
      expect(sale.buyer.avg_rating.to_f).to eq(4.0)
      expect(sale.seller.reload.avg_rating.to_f).to eq(2.0)
    end
  end

  describe "#reveal_now!" do
    it "flips a hidden review visible and refreshes stats" do
      review = create(:review, rating: 3)
      expect { review.reveal_now! }.to change { review.reload.visible }.from(false).to(true)
      expect(review.reviewee.reload.avg_rating.to_f).to eq(3.0)
    end

    it "is idempotent" do
      review = create(:review, :visible)
      expect { review.reveal_now! }.not_to(change { review.reload.revealed_at })
    end
  end

  describe "scopes" do
    it ".overdue_hidden returns only hidden reviews older than the reveal window" do
      old_hidden = create(:review, created_at: (Review::REVEAL_WINDOW + 1.day).ago)
      create(:review, created_at: 1.day.ago)             # recent hidden — excluded
      create(:review, :visible, created_at: 1.year.ago)  # visible — excluded

      expect(Review.overdue_hidden).to contain_exactly(old_hidden)
    end
  end
end
