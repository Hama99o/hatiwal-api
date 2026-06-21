require "rails_helper"

# Covers the server-rendered admin dashboard (Administrate + Devise AdminUser),
# which is entirely separate from the JSON API. Devise's integration helpers
# drive the session login; CSRF is disabled in the test env so form POSTs work
# without a token.
RSpec.describe "Admin dashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }

  describe "authentication gate" do
    it "redirects an unauthenticated visitor from the dashboard to the login page" do
      get admin_root_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "redirects unauthenticated access to a resource index to login" do
      get admin_users_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "renders the login page" do
      get new_admin_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hatiwal Admin")
    end

    it "a marketplace User cannot authenticate into the admin scope" do
      # AdminUser is a separate table; signing in a User must not grant admin.
      user = create(:user)
      sign_in user, scope: :user # scope :user, NOT :admin_user
      get admin_root_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end

  describe "login flow (Admin::SessionsController)" do
    it "signs in with valid credentials and lands on the dashboard" do
      post admin_user_session_path, params: {
        admin_user: { email: admin.email, password: "changeme123!" }
      }
      expect(response).to redirect_to(admin_root_path)
    end

    it "rejects invalid credentials with 422 and does not sign in" do
      post admin_user_session_path, params: {
        admin_user: { email: admin.email, password: "wrong-password" }
      }
      expect(response).to have_http_status(:unprocessable_content)

      get admin_root_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "records trackable sign-in data" do
      expect {
        post admin_user_session_path, params: {
          admin_user: { email: admin.email, password: "changeme123!" }
        }
      }.to change { admin.reload.sign_in_count }.by(1)
    end
  end

  context "when signed in as an admin" do
    before { sign_in admin, scope: :admin_user }

    it "shows the stats dashboard with marketplace counts" do
      create_list(:user, 2)
      create(:listing)

      get admin_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Total users", "Pending reports")
    end

    it "renders every managed resource index" do
      create(:listing)
      create(:report)

      [ admin_users_path, admin_listings_path, admin_reports_path, admin_categories_path ].each do |path|
        get path
        expect(response).to have_http_status(:ok), "expected 200 for #{path}"
      end
    end

    it "renders show pages without choking on attachments" do
      listing = create(:listing)
      get admin_listing_path(listing)
      expect(response).to have_http_status(:ok)
    end

    it "creates a category (write path)" do
      expect {
        post admin_categories_path, params: {
          category: { name_en: "Sports", name_ps: "ورزش", name_fa: "ورزش", slug: "sports-#{SecureRandom.hex(4)}", position: 9, active: true }
        }
      }.to change(Category, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "moderates a user by changing their status" do
      user = create(:user, status: :active)
      patch admin_user_path(user), params: { user: { status: "banned" } }
      expect(response).to have_http_status(:redirect)
      expect(user.reload.status).to eq("banned")
    end

    it "triages a report by updating its status" do
      report = create(:report, status: :pending)
      patch admin_report_path(report), params: { report: { status: "resolved" } }
      expect(report.reload.status).to eq("resolved")
    end

    it "logs out" do
      delete destroy_admin_user_session_path
      expect(response).to redirect_to(new_admin_user_session_path)

      get admin_root_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "blocks a user with a reason via the Block action" do
      user = create(:user, status: :active)
      patch block_admin_user_path(user), params: { block_reason: "Scamming buyers" }
      expect(user.reload.status).to eq("banned")
      expect(user.block_reason).to eq("Scamming buyers")
    end

    it "unblocks a user and clears the reason" do
      user = create(:user, status: :banned, block_reason: "old reason")
      patch unblock_admin_user_path(user)
      expect(user.reload.status).to eq("active")
      expect(user.block_reason).to be_nil
    end

    it "issues a warning to a user via the Warn action" do
      user = create(:user, status: :active)
      expect {
        post warn_admin_user_path(user), params: { reason: "Spam listings", category: "spam" }
      }.to change { user.warnings.count }.by(1)
      expect(user.reload.active_warnings_count).to eq(1)
    end

    it "auto-suspends a user when the third warning is issued" do
      user = create(:user, status: :active)
      create_list(:user_warning, 2, user: user)
      post warn_admin_user_path(user), params: { reason: "third strike" }
      expect(user.reload.status).to eq("suspended")
      expect(user.auto_blocked).to be(true)
    end

    it "takes down a reported listing and resolves the report in one click" do
      listing = create(:listing, :active)
      report = create(:report, reportable: listing, status: :pending)

      patch take_down_target_admin_report_path(report)

      expect(listing.reload.removed?).to be(true)
      expect(report.reload.status).to eq("resolved")
    end

    it "warns the seller of a reported listing and resolves" do
      listing = create(:listing, :active)
      report = create(:report, reportable: listing)

      expect { patch warn_target_admin_report_path(report) }
        .to change { listing.user.warnings.count }.by(1)
      expect(report.reload.status).to eq("resolved")
    end

    it "warns a reported user and resolves" do
      reported = create(:user)
      report = create(:report, :against_user, reportable: reported)

      patch warn_target_admin_report_path(report)

      expect(reported.reload.active_warnings_count).to eq(1)
      expect(report.reload.status).to eq("resolved")
    end

    it "resolves and dismisses a report" do
      report = create(:report, status: :pending)
      patch resolve_admin_report_path(report)
      expect(report.reload.status).to eq("resolved")
      patch dismiss_admin_report_path(report)
      expect(report.reload.status).to eq("dismissed")
    end

    it "renders the report triage page for a listing and a user report" do
      listing_report = create(:report, reportable: create(:listing, :active))
      user_report = create(:report, :against_user, reportable: create(:user))

      get admin_report_path(listing_report)
      expect(response).to have_http_status(:ok)
      get admin_report_path(user_report)
      expect(response).to have_http_status(:ok)
    end

    it "renders the listing take-down page" do
      get admin_listing_path(create(:listing, :active))
      expect(response).to have_http_status(:ok)
    end

    it "records an audit log entry when blocking a user" do
      user = create(:user, status: :active)
      expect {
        patch block_admin_user_path(user), params: { block_reason: "Scam" }
      }.to change(AdminAuditLog, :count).by(1)

      log = AdminAuditLog.last
      expect(log.action).to eq("block_user")
      expect(log.target).to eq(user)
      expect(log.admin_user).to eq(admin)
    end

    it "records an audit entry when taking down a listing from a report" do
      report = create(:report, reportable: create(:listing, :active))
      patch take_down_target_admin_report_path(report)
      expect(AdminAuditLog.where(action: "take_down_listing")).to exist
    end

    it "renders the audit log index and show pages" do
      log = AdminAuditLog.record!(admin_user: admin, action: "block_user", target: create(:user))
      get admin_admin_audit_logs_path
      expect(response).to have_http_status(:ok)
      get admin_admin_audit_log_path(log)
      expect(response).to have_http_status(:ok)
    end

    it "renders the warnings index and show pages" do
      warning = create(:user_warning, admin_user: admin)
      get admin_user_warnings_path
      expect(response).to have_http_status(:ok)
      get admin_user_warning_path(warning)
      expect(response).to have_http_status(:ok)
    end

    it "renders the user-to-user blocks index and show pages" do
      block = create(:block)
      get admin_blocks_path
      expect(response).to have_http_status(:ok)
      get admin_block_path(block)
      expect(response).to have_http_status(:ok)
    end

    it "shows a user's block relationships on their admin page" do
      blocker = create(:user)
      create(:block, blocker: blocker, blocked: create(:user))
      get admin_user_path(blocker)
      expect(response).to have_http_status(:ok)
    end

    it "shows reports against a user (and their listings) on their admin page" do
      seller = create(:user)
      create(:report, reportable: create(:listing, :active, user: seller), reason: :spam)

      get admin_user_path(seller)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Reports against this user")
    end
  end

  describe "managing admin accounts" do
    before { sign_in admin, scope: :admin_user }

    it "renders the admins index, new and edit pages" do
      get admin_admin_users_path
      expect(response).to have_http_status(:ok)
      get new_admin_admin_user_path
      expect(response).to have_http_status(:ok)
      get edit_admin_admin_user_path(admin)
      expect(response).to have_http_status(:ok)
    end

    it "creates a new admin account" do
      expect {
        post admin_admin_users_path, params: {
          admin_user: { name: "New Mod", email: "mod@hatiwal.com", password: "changeme123!" }
        }
      }.to change(AdminUser, :count).by(1)
      expect(AdminUser.find_by(email: "mod@hatiwal.com")).to be_present
    end

    it "keeps the current password when the field is left blank on edit" do
      other = create(:admin_user, password: "original123!")
      patch admin_admin_user_path(other), params: {
        admin_user: { name: "Renamed", email: other.email, password: "" }
      }
      expect(other.reload.name).to eq("Renamed")
      expect(other.valid_password?("original123!")).to be(true)
    end

    it "won't let an admin delete their own account" do
      create(:admin_user) # so admin isn't the last one
      expect { delete admin_admin_user_path(admin) }.not_to change(AdminUser, :count)
    end

    it "deletes another admin account" do
      other = create(:admin_user)
      expect { delete admin_admin_user_path(other) }.to change(AdminUser, :count).by(-1)
    end
  end

  describe "account lockout (lockable)" do
    it "locks the account after the configured maximum failed attempts" do
      Devise.maximum_attempts.times do
        post admin_user_session_path, params: {
          admin_user: { email: admin.email, password: "wrong-password" }
        }
      end
      expect(admin.reload.access_locked?).to be(true)
    end
  end
end
