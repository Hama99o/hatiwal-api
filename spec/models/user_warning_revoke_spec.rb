require "rails_helper"

# "Revoke warning" (owner, 2026-10-19): an admin cancels a warning given by
# mistake. It stops counting at once, the person no longer sees it, the row stays.
RSpec.describe UserWarning, "#revoke!" do
  let(:admin) { create(:admin_user) }

  it "stops counting at once and keeps the row with who and why" do
    user = create(:user)
    warning = user.issue_warning!(admin_user: admin, reason: "Spam")

    expect(warning.revoke!(admin_user: admin, reason: "Wrong person")).to be(true)

    warning.reload
    expect(warning).to be_revoked
    expect(warning).not_to be_active
    expect([ warning.revoked_by, warning.revoke_reason ]).to eq([ admin, "Wrong person" ])
    expect(user.active_warnings_count).to eq(0)
    expect(UserWarning.expired).to include(warning)
    expect(UserWarning.active).not_to include(warning)
  end

  it "is a no-op the second time" do
    warning = create(:user_warning)
    warning.revoke!(admin_user: admin, reason: "Mistake")
    expect(warning.revoke!(admin_user: admin, reason: "Again")).to be(false)
    expect(warning.reload.revoke_reason).to eq("Mistake")
  end

  it "reinstates a user auto-suspended by 3 strikes when one is revoked" do
    user = create(:user)
    warnings = Array.new(3) { user.issue_warning!(admin_user: admin, reason: "Spam") }
    expect(user.reload).to be_suspended

    warnings.last.revoke!(admin_user: admin, reason: "Appeal accepted")

    expect(user.reload).to be_active
    expect(user.active_warnings_count).to eq(2)
  end

  it "never lifts a manual ban" do
    user = create(:user)
    warning = user.issue_warning!(admin_user: admin, reason: "Spam")
    user.update!(status: :banned, auto_blocked: false)

    warning.revoke!(admin_user: admin, reason: "Mistake")

    expect(user.reload).to be_banned
  end

  it "lowers a shop's count but leaves a suspended shop suspended (the admin decides)" do
    shop = create(:shop)
    warnings = Array.new(3) { shop.issue_warning!(admin_user: admin, reason: "Prohibited") }
    expect(shop.reload).to be_suspended

    warnings.first.revoke!(admin_user: admin, reason: "Mistake")

    expect(shop.active_warnings_count).to eq(2)
    expect(shop.reload).to be_suspended
  end

  # Two admins (or a double click: the admin has no rails-ujs disable-with) can
  # send two revokes at once; each request loads the row before the other
  # writes. The second must see the first and change nothing (QA 2026-10-19:
  # both went through, the second reason overwrote the first, two audit rows).
  it "refuses a revoke from a stale copy of an already revoked warning" do
    warning = create(:user_warning)
    stale = UserWarning.find(warning.id)

    expect(warning.revoke!(admin_user: admin, reason: "First")).to be(true)
    expect(stale.revoke!(admin_user: admin, reason: "Second")).to be(false)

    expect(warning.reload.revoke_reason).to eq("First")
  end
end
