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
end
