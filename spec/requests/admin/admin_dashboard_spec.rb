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
