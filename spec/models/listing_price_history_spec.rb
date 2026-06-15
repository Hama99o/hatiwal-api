require "rails_helper"

RSpec.describe ListingPriceHistory, type: :model do
  describe "associations" do
    it { should belong_to(:listing) }
  end

  describe "validations" do
    subject { build(:listing_price_history) }

    it { should validate_presence_of(:old_price) }
    it { should validate_presence_of(:new_price) }
    it { should validate_presence_of(:currency) }
    it { should validate_presence_of(:changed_at) }

    it { should validate_numericality_of(:old_price).is_greater_than(0) }
    it { should validate_numericality_of(:new_price).is_greater_than(0) }

    it {
      should validate_inclusion_of(:currency).in_array(%w[AFN USD EUR])
    }
  end

  describe "scopes" do
    let(:listing) { create(:listing) }

    describe ".reductions" do
      it "returns only records where new_price < old_price" do
        drop     = create(:listing_price_history, listing: listing, old_price: 5000, new_price: 4000, changed_at: 1.day.ago)
        _increase = create(:listing_price_history, :increase, listing: listing, changed_at: 2.days.ago)

        expect(ListingPriceHistory.reductions).to contain_exactly(drop)
      end
    end

    describe ".recent" do
      it "returns only records within the last 14 days" do
        recent = create(:listing_price_history, :recent_drop, listing: listing)
        _old   = create(:listing_price_history, :old_drop, listing: listing)

        expect(ListingPriceHistory.recent(14)).to contain_exactly(recent)
      end
    end
  end

  describe ".record_change!" do
    let(:listing) { create(:listing, price: 10_000, currency: "AFN") }

    it "creates a price history record with the correct values" do
      history = ListingPriceHistory.record_change!(
        listing:   listing,
        old_price: 10_000,
        new_price: 8_000
      )

      expect(history).to be_persisted
      expect(history.old_price).to eq(10_000)
      expect(history.new_price).to eq(8_000)
      expect(history.currency).to eq("AFN")
      expect(history.changed_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#drop_percent" do
    it "returns the integer percent reduction" do
      history = build(:listing_price_history, old_price: 10_000, new_price: 8_000)
      expect(history.drop_percent).to eq(20)
    end

    it "returns 0 when not a reduction" do
      history = build(:listing_price_history, :increase)
      expect(history.drop_percent).to eq(0)
    end

    it "rounds correctly for fractional percentages" do
      history = build(:listing_price_history, old_price: 1000, new_price: 850)
      expect(history.drop_percent).to eq(15)
    end
  end
end
