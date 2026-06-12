require "rails_helper"

RSpec.describe Conversation, type: :model do
  describe "associations" do
    it { should belong_to(:listing) }
    it { should belong_to(:buyer).class_name("User") }
    it { should belong_to(:seller).class_name("User") }
    it { should have_many(:messages).dependent(:destroy) }
  end

  describe "validations" do
    it "prevents duplicate conversations for same listing + buyer" do
      listing  = create(:listing, :active)
      buyer    = create(:user)
      create(:conversation, listing: listing, buyer: buyer, seller: listing.user)
      dup = build(:conversation, listing: listing, buyer: buyer, seller: listing.user)
      expect(dup).not_to be_valid
    end

    it "prevents buyer == seller" do
      user = create(:user)
      listing = create(:listing, :active, user: user)
      conv = build(:conversation, listing: listing, buyer: user, seller: user)
      expect(conv).not_to be_valid
    end
  end

  describe "enums" do
    it { should define_enum_for(:status).with_values(open: 0, closed: 1) }
  end

  describe "scopes" do
    describe ".ordered" do
      it "orders by last_message_at desc" do
        older = create(:conversation, last_message_at: 2.hours.ago)
        newer = create(:conversation, last_message_at: 1.minute.ago)
        expect(Conversation.ordered.first).to eq(newer)
        expect(Conversation.ordered.last).to eq(older)
      end
    end

    describe ".for_user" do
      it "returns conversations where the user is buyer or seller" do
        user = create(:user)
        as_buyer  = create(:conversation, buyer: user, listing: create(:listing))
        as_seller = create(:conversation, listing: create(:listing, user: user))
        create(:conversation) # unrelated

        expect(Conversation.for_user(user.id)).to contain_exactly(as_buyer, as_seller)
      end
    end
  end

  describe "#participant?" do
    it "returns true for buyer and seller" do
      conv = create(:conversation)
      expect(conv.participant?(conv.buyer)).to be true
      expect(conv.participant?(conv.seller)).to be true
    end

    it "returns false for other users" do
      conv = create(:conversation)
      other = create(:user)
      expect(conv.participant?(other)).to be false
    end
  end

  describe "#other_participant" do
    it "returns the seller when asked from the buyer's perspective" do
      conv = create(:conversation)
      expect(conv.other_participant(conv.buyer)).to eq(conv.seller)
    end

    it "returns the buyer when asked from the seller's perspective" do
      conv = create(:conversation)
      expect(conv.other_participant(conv.seller)).to eq(conv.buyer)
    end
  end
end
