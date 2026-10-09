require "rails_helper"

# d0 hunt 2026-10-09 (supervisor: critical, server-only, 1.1.6).
RSpec.describe "Admin safety: one strike per report, no hard delete, logged moderation", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }
  before { sign_in admin, scope: :admin_user }

  describe "Warn & resolve" do
    # It showed whatever the report's status, had no confirm and no guard: 3
    # clicks (or a double-click on a non-Turbo form) = 3 strikes = auto-suspend.
    it "gives ONE strike per report, however often it is sent" do
      reported = create(:user)
      report = create(:report, :against_user, reportable: reported)
      3.times { patch warn_target_admin_report_path(report) }
      expect(reported.reload.active_warnings_count).to eq(1)
      expect(reported).to be_active
      expect(report.reload).to be_resolved
    end
  end

  describe "Destroy a user" do
    # Administrate's default hard-deleted the user; dependent: :destroy on their
    # conversations and messages wiped the OTHER party's chat history, unlogged.
    it "anonymizes instead of deleting: the other party keeps the chat, and it is logged" do
      seller = create(:user)
      buyer = create(:user)
      chat = Conversations::StartService.new(buyer: buyer, listing: create(:listing, :active, user: seller), message_body: "Hi").call

      delete admin_user_path(seller)

      expect(User.exists?(seller.id)).to be(true)
      expect(seller.reload.deleted_at).to be_present
      expect(Conversation.exists?(chat.id)).to be(true)
      expect(chat.messages.count).to eq(1)
      expect(AdminAuditLog.where(action: "anonymize_user", target: seller)).to exist
    end
  end

  describe "Edit a user" do
    let(:user) { create(:user, email: "keep@example.com") }

    # status / block_reason / email edits bypassed Block / Unblock (no audit
    # line, no clear_active_warnings!) and changed the login email unlogged.
    it "status, block reason and email are not editable there (use Block / Unblock / Confirm email)" do
      patch admin_user_path(user), params: { user: { status: "banned", block_reason: "x", email: "new@example.com" } }
      user.reload
      expect(user).to be_active
      expect(user.block_reason).to be_nil
      expect(user.email).to eq("keep@example.com")
    end

    it "switching the badge OFF there is refused (use Remove badge, which writes the decision and tells them)" do
      user.update_columns(verified: true)
      patch admin_user_path(user), params: { user: { verified: "0" } }
      expect(user.reload.verified).to be(true)
    end

    it "switching the badge ON there is logged" do
      patch admin_user_path(user), params: { user: { verified: "1" } }
      expect(user.reload.verified).to be(true)
      expect(AdminAuditLog.where(action: "verified_on", target: user)).to exist
    end
  end
end
