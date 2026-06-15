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

    it "creates a view the first time and returns newly_created true" do
      result = nil
      expect { result = ListingView.record!(user, listing) }.to change(ListingView, :count).by(1)
      _view, newly_created = result
      expect(newly_created).to be true
    end

    it "does not duplicate on subsequent views and returns newly_created false" do
      view, = ListingView.record!(user, listing)
      view.update_column(:last_viewed_at, 1.hour.ago)
      old_time = view.reload.last_viewed_at

      result = nil
      expect { result = ListingView.record!(user, listing) }.not_to change(ListingView, :count)
      _view2, newly_created = result
      expect(newly_created).to be false
      expect(view.reload.last_viewed_at).to be > old_time
    end
  end
end
