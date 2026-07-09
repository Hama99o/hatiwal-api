require "rails_helper"

RSpec.describe RevealOverdueReviewsJob, type: :job do
  it "reveals hidden reviews past the reveal window and refreshes stats" do
    overdue = create(:review, rating: 4, created_at: (Review::REVEAL_WINDOW + 1.day).ago)
    recent  = create(:review, created_at: 1.day.ago)

    described_class.new.perform

    expect(overdue.reload.visible).to be(true)
    expect(overdue.reviewee.reload.avg_rating.to_f).to eq(4.0)
    expect(recent.reload.visible).to be(false)
  end
end
