require "rails_helper"

# The strike system: warnings accumulate, auto-suspend at the threshold, decay
# over time, and an auto-suspension lifts once warnings drop below the threshold.
RSpec.describe "User strikes", type: :model do
  let(:admin) { create(:admin_user) }

  describe "#issue_warning!" do
    it "adds an active warning" do
      user = create(:user)
      expect { user.issue_warning!(admin_user: admin, reason: "Spam", category: :spam) }
        .to change { user.active_warnings_count }.from(0).to(1)
    end

    it "auto-suspends when the active count reaches the threshold" do
      user = create(:user, status: :active)

      2.times { user.issue_warning!(admin_user: admin, reason: "x") }
      expect(user.status).to eq("active")

      user.issue_warning!(admin_user: admin, reason: "third")
      expect(user.reload.status).to eq("suspended")
      expect(user.auto_blocked).to be(true)
      expect(user.account_blocked?).to be(true)
    end

    it "ignores decayed warnings when counting toward the threshold" do
      user = create(:user, status: :active)
      create_list(:user_warning, 2, :expired, user: user) # already decayed

      user.issue_warning!(admin_user: admin, reason: "fresh")

      expect(user.active_warnings_count).to eq(1)
      expect(user.reload.status).to eq("active")
    end
  end

  describe "#warnings_remaining" do
    it "counts down from the threshold" do
      user = create(:user)
      user.issue_warning!(admin_user: admin, reason: "x")
      expect(user.warnings_remaining).to eq(User::WARNING_BLOCK_THRESHOLD - 1)
    end
  end

  describe "#reinstate_if_decayed!" do
    it "lifts an auto-suspension once warnings decay below the threshold" do
      user = create(:user, status: :active)
      3.times { user.issue_warning!(admin_user: admin, reason: "x") }
      expect(user.reload.status).to eq("suspended")

      user.warnings.active.first.update!(expires_at: 1.day.ago) # decay one → 2 active

      expect(user.reinstate_if_decayed!).to be(true)
      expect(user.reload.status).to eq("active")
      expect(user.auto_blocked).to be(false)
    end

    it "never lifts a manual ban" do
      user = create(:user, status: :banned, auto_blocked: false)
      expect(user.reinstate_if_decayed!).to be(false)
      expect(user.reload.status).to eq("banned")
    end
  end

  describe "#clear_active_warnings!" do
    it "expires all active warnings (clean slate)" do
      user = create(:user)
      create_list(:user_warning, 2, user: user)
      expect { user.clear_active_warnings! }.to change { user.active_warnings_count }.from(2).to(0)
    end
  end
end
