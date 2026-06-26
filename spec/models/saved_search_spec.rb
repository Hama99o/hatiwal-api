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

  describe "#new_matches_count" do
    include ActiveSupport::Testing::TimeHelpers

    let(:cat) { create(:category) }
    let(:seller) { create(:user) }

    # Helper: create a listing first, then back-date its created_at via
    # update_column (bypasses ActiveRecord timestamp guards).
    # Accepts optional trait symbols followed by keyword overrides:
    #   create_listing_at(1.hour.ago, :active, user: seller, category: cat)
    def create_listing_at(time, *traits, **attrs)
      listing = create(:listing, *traits, **attrs)
      listing.update_column(:created_at, time)
      listing
    end

    # Use location: nil to avoid the factory default (Faker city) accidentally
    # filtering listings by location text.

    it "counts browsable listings created after last_viewed_at" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(1)
    end

    it "uses created_at as baseline when last_viewed_at is nil" do
      travel_to(3.hours.ago) { @ss = create(:saved_search, user: user, location: nil, last_viewed_at: nil) }
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)

      expect(@ss.new_matches_count).to eq(1)
    end

    it "excludes listings created before last_viewed_at" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 1.hour.ago)
      create_listing_at(2.hours.ago, :active, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes draft listings" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, status: :draft, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes sold listings" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, status: :sold, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes reserved listings" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, status: :reserved, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes expired listings" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      listing = create_listing_at(1.hour.ago, :active, user: seller, category: cat)
      listing.update_column(:expires_at, 30.minutes.ago)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes removed listings" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      listing = create_listing_at(1.hour.ago, :active, user: seller, category: cat)
      listing.update_column(:removed_at, 30.minutes.ago)

      expect(ss.new_matches_count).to eq(0)
    end

    it "filters by category_id when set" do
      other_cat = create(:category)
      ss = create(:saved_search, user: user, location: nil, category: cat, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)
      create_listing_at(1.hour.ago, :active, user: seller, category: other_cat)

      expect(ss.new_matches_count).to eq(1)
    end

    it "filters by price_min when set" do
      ss = create(:saved_search, user: user, location: nil, price_min: 5000, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat, price: 3000)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat, price: 7000)

      expect(ss.new_matches_count).to eq(1)
    end

    it "filters by price_max when set" do
      ss = create(:saved_search, user: user, location: nil, price_max: 5000, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat, price: 3000)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat, price: 7000)

      expect(ss.new_matches_count).to eq(1)
    end

    it "filters by location text when not location_based" do
      ss = create(:saved_search, user: user, location: "Kabul", last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat, location: "Kabul, Afghanistan")
      create_listing_at(1.hour.ago, :active, user: seller, category: cat, location: "Kandahar")

      expect(ss.new_matches_count).to eq(1)
    end

    it "returns 0 when there are no new matches" do
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 1.hour.ago)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes listings from a seller the owner has blocked" do
      # owner blocks seller — the seller's new listing must NOT inflate the badge
      create(:block, blocker: user, blocked: seller)
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(0)
    end

    it "excludes listings from a seller who has blocked the owner" do
      # seller blocks owner — the seller's new listing must NOT inflate the badge
      create(:block, blocker: seller, blocked: user)
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)

      expect(ss.new_matches_count).to eq(0)
    end

    it "still counts listings from non-blocked sellers" do
      # blocking only affects the blocked seller; an unrelated seller's listing is counted
      other_seller = create(:user)
      create(:block, blocker: user, blocked: seller)
      ss = create(:saved_search, user: user, location: nil, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller,       category: cat)
      create_listing_at(1.hour.ago, :active, user: other_seller, category: cat)

      expect(ss.new_matches_count).to eq(1)
    end
  end
end
