require "rails_helper"

RSpec.describe HiddenListing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:listing) }
  end

  describe "validations" do
    it "prevents the same user hiding the same listing twice" do
      user    = create(:user)
      listing = create(:listing)
      create(:hidden_listing, user: user, listing: listing)
      dup = build(:hidden_listing, user: user, listing: listing)

      expect(dup).not_to be_valid
      expect(dup.errors[:listing_id]).to be_present
    end

    it "allows different users to hide the same listing" do
      listing = create(:listing)
      create(:hidden_listing, user: create(:user), listing: listing)
      other = build(:hidden_listing, user: create(:user), listing: listing)
      expect(other).to be_valid
    end

    it "allows the same user to hide different listings" do
      user = create(:user)
      create(:hidden_listing, user: user, listing: create(:listing))
      another = build(:hidden_listing, user: user, listing: create(:listing))
      expect(another).to be_valid
    end
  end

  describe "scopes" do
    describe ".ordered" do
      it "returns newest hides first" do
        old   = create(:hidden_listing, created_at: 2.days.ago)
        fresh = create(:hidden_listing, created_at: 1.hour.ago)
        expect(HiddenListing.ordered.first).to eq(fresh)
        expect(HiddenListing.ordered.last).to eq(old)
      end
    end
  end
end
