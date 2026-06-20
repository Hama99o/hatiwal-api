require "rails_helper"

RSpec.describe UserWarning, type: :model do
  it "defaults expires_at to ACTIVE_PERIOD from creation" do
    warning = create(:user_warning)
    expect(warning.expires_at).to be_within(1.minute).of(UserWarning::ACTIVE_PERIOD.from_now)
  end

  it "the active scope excludes decayed (expired) warnings" do
    active = create(:user_warning)
    create(:user_warning, :expired)

    expect(UserWarning.active).to contain_exactly(active)
    expect(UserWarning.expired.count).to eq(1)
  end

  it "#active? reflects the expiry" do
    expect(create(:user_warning).active?).to be(true)
    expect(create(:user_warning, :expired).active?).to be(false)
  end
end
