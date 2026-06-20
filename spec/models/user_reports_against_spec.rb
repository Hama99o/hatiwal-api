require "rails_helper"

RSpec.describe "User#reports_against", type: :model do
  it "includes reports against the user directly and against their listings" do
    user = create(:user)
    against_user = create(:report, :against_user, reportable: user)
    listing = create(:listing, :active, user: user)
    against_listing = create(:report, reportable: listing)
    unrelated = create(:report)

    ids = user.reports_against.pluck(:id)

    expect(ids).to include(against_user.id, against_listing.id)
    expect(ids).not_to include(unrelated.id)
  end
end
