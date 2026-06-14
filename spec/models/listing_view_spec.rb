require "rails_helper"

RSpec.describe ListingView, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:listing) }
  end

  describe "validations" do
    subject { create(:listing_view) }
    it { is_expected.to validate_uniqueness_of(:listing_id).scoped_to(:user_id) }
  end

  describe ".record!" do
    let(:user) { create(:user) }
    let(:listing) { create(:listing) }

    it "creates a view the first time" do
      expect { ListingView.record!(user, listing) }.to change(ListingView, :count).by(1)
    end

    it "does not duplicate on subsequent views, but refreshes last_viewed_at" do
      first = ListingView.record!(user, listing)
      first.update_column(:last_viewed_at, 1.hour.ago)
      old_time = first.reload.last_viewed_at

      expect { ListingView.record!(user, listing) }.not_to change(ListingView, :count)
      expect(first.reload.last_viewed_at).to be > old_time
    end
  end
end
