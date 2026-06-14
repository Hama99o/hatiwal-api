require "rails_helper"

RSpec.describe SavedSearch, type: :model do
  let(:user) { create(:user) }
  let(:category) { create(:category) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:category).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_numericality_of(:latitude).is_greater_than_or_equal_to(-90).is_less_than_or_equal_to(90).allow_nil }
    it { is_expected.to validate_numericality_of(:longitude).is_greater_than_or_equal_to(-180).is_less_than_or_equal_to(180).allow_nil }
    it { is_expected.to validate_numericality_of(:radius).is_greater_than(0).is_less_than_or_equal_to(100).allow_nil }
  end

  describe "#location_based?" do
    it "returns true when all coordinates and radius are present" do
      ss = create(:saved_search, latitude: 34.52, longitude: 69.18, radius: 5)
      expect(ss.location_based?).to be true
    end

    it "returns false when any coordinate is missing" do
      ss = create(:saved_search, latitude: 34.52, longitude: 69.18, radius: nil)
      expect(ss.location_based?).to be false
    end
  end

  describe "scopes" do
    it "orders by created_at descending" do
      ss1 = create(:saved_search, user: user, created_at: 1.day.ago)
      ss2 = create(:saved_search, user: user, created_at: 2.days.ago)

      expect(SavedSearch.recent.first).to eq(ss1)
      expect(SavedSearch.recent.last).to eq(ss2)
    end

    it ".for_user returns only that user's searches" do
      other_user = create(:user)
      create(:saved_search, user: user)
      create(:saved_search, user: other_user)

      results = SavedSearch.for_user(user)
      expect(results.count).to eq(1)
      expect(results.first.user_id).to eq(user.id)
    end
  end
end
