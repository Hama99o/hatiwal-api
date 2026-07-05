require "rails_helper"

RSpec.describe SavedListing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:listing) }
  end

  describe "validations" do
    it "prevents the same user saving the same listing twice" do
      user    = create(:user)
      listing = create(:listing)
      create(:saved_listing, user: user, listing: listing)
      dup = build(:saved_listing, user: user, listing: listing)

      expect(dup).not_to be_valid
      expect(dup.errors[:listing_id]).to be_present
    end

    it "allows different users to save the same listing" do
      listing = create(:listing)
      create(:saved_listing, user: create(:user), listing: listing)
      other = build(:saved_listing, user: create(:user), listing: listing)
      expect(other).to be_valid
    end

    it "allows the same user to save different listings" do
      user = create(:user)
      create(:saved_listing, user: user, listing: create(:listing))
      another = build(:saved_listing, user: user, listing: create(:listing))
      expect(another).to be_valid
    end
  end

  describe "scopes" do
    describe ".ordered" do
      it "returns newest saves first" do
        old   = create(:saved_listing, created_at: 2.days.ago)
        fresh = create(:saved_listing, created_at: 1.hour.ago)
        expect(SavedListing.ordered.first).to eq(fresh)
        expect(SavedListing.ordered.last).to eq(old)
      end
    end
  end

  describe "#price_at_save" do
    it "snapshots the listing's price on create" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      expect(saved.price_at_save).to eq(5000)
    end

    it "does not change the snapshot when the listing price changes later" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      listing.update!(price: 4000)
      expect(saved.reload.price_at_save).to eq(5000)
    end
  end

  describe "#price_dropped?" do
    it "is true when the current price is lower than price_at_save and the listing is active" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      listing.update!(price: 4000)
      expect(saved.reload.price_dropped?).to be true
    end

    it "is false when the price is unchanged" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      expect(saved.price_dropped?).to be false
    end

    it "is false when the price increased" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      listing.update!(price: 6000)
      expect(saved.reload.price_dropped?).to be false
    end

    it "is false when the listing is no longer active, even if the price dropped" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      listing.update!(price: 4000, status: :sold)
      expect(saved.reload.price_dropped?).to be false
    end
  end

  describe "#price_drop_amount" do
    it "returns the positive drop amount when the price dropped" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      listing.update!(price: 4000)
      expect(saved.reload.price_drop_amount).to eq(1000)
    end

    it "returns nil when the price did not drop" do
      listing = create(:listing, :active, price: 5000)
      saved = create(:saved_listing, listing: listing)
      expect(saved.price_drop_amount).to be_nil
    end
  end
end
