require "rails_helper"

# IDEA-6: anyone (a guest too) reads the switched-on spots; only an admin edits.
RSpec.describe MeetupSpotPolicy do
  let!(:shown) { create(:meetup_spot) }
  let!(:draft) { create(:meetup_spot, active: false, needs_local_check: true) }

  it "lets anyone list, and the scope is the switched-on rows only" do
    expect(described_class.new(nil, MeetupSpot).index?).to be true
    expect(described_class::Scope.new(nil, MeetupSpot).resolve).to eq([ shown ])
  end

  it "admin policy: an AdminUser edits; a marketplace user never does" do
    admin = Admin::MeetupSpotPolicy.new(create(:admin_user), draft)
    user  = Admin::MeetupSpotPolicy.new(create(:user), draft)
    expect(%i[index? create? update? destroy?].map { |a| admin.public_send(a) }).to all(be true)
    expect(%i[index? create? update? destroy?].map { |a| user.public_send(a) }).to all(be false)
    expect(Admin::MeetupSpotPolicy::Scope.new(create(:user), MeetupSpot).resolve).to be_empty
  end
end
