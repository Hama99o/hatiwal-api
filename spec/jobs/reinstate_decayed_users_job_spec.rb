require "rails_helper"

RSpec.describe ReinstateDecayedUsersJob, type: :job do
  let(:admin) { create(:admin_user) }

  it "reinstates an auto-suspended user whose warnings have decayed" do
    user = create(:user, status: :active)
    3.times { user.issue_warning!(admin_user: admin, reason: "x") }
    expect(user.reload.status).to eq("suspended")

    user.warnings.active.first.update!(expires_at: 1.day.ago) # now 2 active

    described_class.perform_now
    expect(user.reload.status).to eq("active")
  end

  it "leaves a user with enough active warnings suspended" do
    user = create(:user, status: :active)
    3.times { user.issue_warning!(admin_user: admin, reason: "x") }

    described_class.perform_now
    expect(user.reload.status).to eq("suspended")
  end

  it "never reinstates a manual ban" do
    user = create(:user, status: :banned, auto_blocked: false)
    described_class.perform_now
    expect(user.reload.status).to eq("banned")
  end
end
