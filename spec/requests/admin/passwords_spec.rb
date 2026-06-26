require "rails_helper"

RSpec.describe "Admin::PasswordsController", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }

  # ── GET /admin/password/new ──────────────────────────────────────────────────

  describe "GET /admin/password/new" do
    it "renders the forgot-password form" do
      get new_admin_user_password_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Forgot password")
    end

    it "does not include a reset_password_token hidden field (belongs only in edit form)" do
      get new_admin_user_password_path
      expect(response.body).not_to include('name="admin_user[reset_password_token]"')
    end
  end

  # ── POST /admin/password ─────────────────────────────────────────────────────

  describe "POST /admin/password" do
    it "enqueues a branded reset email for a known email" do
      expect do
        post admin_user_password_path, params: { admin_user: { email: admin.email } }
      end.to have_enqueued_mail(AdminUserMailer, :reset_password_instructions)
    end

    it "redirects to the login page after sending" do
      post admin_user_password_path, params: { admin_user: { email: admin.email } }
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "does NOT reveal whether the email exists (same redirect for unknown email)" do
      post admin_user_password_path, params: { admin_user: { email: "nobody@example.com" } }
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end

  # ── GET /admin/password/edit ─────────────────────────────────────────────────

  describe "GET /admin/password/edit" do
    it "renders the set-new-password form when given a valid token" do
      token = admin.send_reset_password_instructions
      get edit_admin_user_password_path(reset_password_token: token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Set new password")
    end
  end

  # ── PUT /admin/password ──────────────────────────────────────────────────────

  describe "PUT /admin/password" do
    context "with a valid token and matching passwords" do
      it "updates the password and redirects to login" do
        token = admin.send_reset_password_instructions

        put admin_user_password_path, params: {
          admin_user: {
            reset_password_token: token,
            password: "newstrongpass1!",
            password_confirmation: "newstrongpass1!"
          }
        }

        expect(response).to redirect_to(new_admin_user_session_path)
        expect(admin.reload.valid_password?("newstrongpass1!")).to be(true)
      end
    end

    context "with an invalid token" do
      it "re-renders the edit form with an error" do
        put admin_user_password_path, params: {
          admin_user: {
            reset_password_token: "bogus-token",
            password: "newstrongpass1!",
            password_confirmation: "newstrongpass1!"
          }
        }

        expect(response).not_to redirect_to(new_admin_user_session_path)
      end
    end

    context "when passwords do not match" do
      it "re-renders the edit form with an error" do
        token = admin.send_reset_password_instructions

        put admin_user_password_path, params: {
          admin_user: {
            reset_password_token: token,
            password: "newstrongpass1!",
            password_confirmation: "differentpass2!"
          }
        }

        expect(response).not_to redirect_to(new_admin_user_session_path)
      end
    end
  end

  # ── AdminUserMailer content ──────────────────────────────────────────────────

  describe "AdminUserMailer#reset_password_instructions" do
    it "sends to the admin's email with a Hatiwal Admin subject" do
      token = admin.send_reset_password_instructions
      mail = AdminUserMailer.reset_password_instructions(admin, token)
      expect(mail.to).to eq([ admin.email ])
      expect(mail.subject).to include("Hatiwal Admin")
    end

    it "includes the reset token in the email body" do
      token = admin.send_reset_password_instructions
      mail = AdminUserMailer.reset_password_instructions(admin, token)
      expect(mail.body.encoded).to include(token)
    end
  end
end
