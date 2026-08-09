require "rails_helper"

RSpec.describe Transaction, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:listing) }
    it { is_expected.to belong_to(:seller).class_name("User") }
    it { is_expected.to belong_to(:buyer).class_name("User") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:final_price) }
    it { is_expected.to validate_presence_of(:currency) }

    it "is valid with a conversation-participant buyer" do
      txn = build(:transaction)
      expect(txn).to be_valid
    end

    it "is invalid when the buyer equals the seller" do
      seller  = create(:user)
      listing = create(:listing, :active, user: seller)
      txn = build(:transaction, listing: listing, seller: seller, buyer: seller)

      expect(txn).not_to be_valid
      expect(txn.errors[:buyer_id]).to be_present
    end

    it "is invalid when the buyer never had a conversation on this listing" do
      seller  = create(:user)
      listing = create(:listing, :active, user: seller)
      stranger = create(:user)
      txn = Transaction.new(listing: listing, seller: seller, buyer: stranger, final_price: listing.price, currency: listing.currency)

      expect(txn).not_to be_valid
      expect(txn.errors[:buyer_id]).to include(a_string_matching(/participant/))
    end
  end

  describe "#mark_sold!" do
    it "advances a reserved transaction to sold, sets completed_at" do
      txn = create(:transaction, status: :reserved)

      expect { txn.mark_sold! }.to change { txn.reload.status }.from("reserved").to("sold")
      expect(txn.completed_at).to be_present
    end

    it "accepts an updated final_price and buyer_id" do
      seller  = create(:user)
      listing = create(:listing, :active, user: seller)
      buyer1  = create(:user)
      buyer2  = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: buyer1)
      create(:conversation, listing: listing, seller: seller, buyer: buyer2)
      txn = create(:transaction, listing: listing, seller: seller, buyer: buyer1, final_price: 1000)

      txn.mark_sold!(final_price: 900, buyer_id: buyer2.id)

      expect(txn.reload.final_price.to_i).to eq(900)
      expect(txn.buyer_id).to eq(buyer2.id)
    end
  end

  describe "trust-stat counters (TASK-TX02)" do
    it "bumps seller.sold_count and buyer.bought_count when created directly as sold" do
      seller  = create(:user)
      buyer   = create(:user)
      listing = create(:listing, :active, user: seller)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)

      expect do
        create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)
      end.to change { seller.reload.sold_count }.by(1)
              .and change { buyer.reload.bought_count }.by(1)
    end

    it "bumps counters when a reserved transaction is advanced to sold via #mark_sold!" do
      txn = create(:transaction, status: :reserved)

      expect { txn.mark_sold! }
        .to change { txn.seller.reload.sold_count }.by(1)
        .and change { txn.buyer.reload.bought_count }.by(1)
    end

    it "does not bump counters while a transaction stays reserved" do
      seller = create(:user)
      buyer  = create(:user)
      create(:transaction, status: :reserved, seller: seller, buyer: buyer)

      expect(seller.reload.sold_count).to eq(0)
      expect(buyer.reload.bought_count).to eq(0)
    end

    it "does not double-count when an already-sold transaction is saved again" do
      txn = create(:transaction, :sold)

      expect { txn.update!(final_price: txn.final_price + 1) }
        .not_to change { txn.seller.reload.sold_count }
      expect(txn.buyer.reload.bought_count).to eq(1)
    end

    it "never counts the seller and buyer of two different sales into each other" do
      seller_a = create(:user)
      buyer_a  = create(:user)
      seller_b = create(:user)
      buyer_b  = create(:user)
      create(:transaction, :sold, seller: seller_a, buyer: buyer_a,
                                  listing: create(:listing, :active, user: seller_a))
      create(:transaction, :sold, seller: seller_b, buyer: buyer_b,
                                  listing: create(:listing, :active, user: seller_b))

      expect(seller_a.reload.sold_count).to eq(1)
      expect(seller_a.reload.bought_count).to eq(0)
      expect(buyer_a.reload.bought_count).to eq(1)
      expect(buyer_a.reload.sold_count).to eq(0)
      expect(seller_b.reload.sold_count).to eq(1)
      expect(buyer_b.reload.bought_count).to eq(1)
    end
  end

  describe "scopes" do
    it ".as_buyer / .as_seller / .for_user" do
      user_a = create(:user)

      # user_a as buyer on someone else's listing
      as_buyer_txn = create(:transaction, buyer: user_a)

      # user_a as seller (the listing owner) on their own listing
      sellers_listing = create(:listing, :active, user: user_a)
      as_seller_txn = create(:transaction, listing: sellers_listing, seller: user_a)

      # unrelated transaction — user_a is neither buyer nor seller
      create(:transaction)

      expect(Transaction.as_buyer(user_a)).to contain_exactly(as_buyer_txn)
      expect(Transaction.as_seller(user_a)).to contain_exactly(as_seller_txn)
      expect(Transaction.for_user(user_a)).to contain_exactly(as_buyer_txn, as_seller_txn)
    end
  end

  describe "DB constraint" do
    it "prevents two OPEN (reserved) transactions on the same listing" do
      seller  = create(:user)
      listing = create(:listing, :active, user: seller)
      buyer1  = create(:user)
      buyer2  = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: buyer1)
      create(:conversation, listing: listing, seller: seller, buyer: buyer2)
      create(:transaction, listing: listing, seller: seller, buyer: buyer1, status: :reserved)

      expect do
        Transaction.create!(listing: listing, seller: seller, buyer: buyer2, final_price: listing.price, currency: listing.currency, status: :reserved)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
