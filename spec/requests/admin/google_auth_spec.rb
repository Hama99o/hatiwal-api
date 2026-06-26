# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::GoogleAuth", type: :request do
  let!(:admin) { create(:admin_user, email: "admin@hatiwal.com") }

  let(:valid_token_response) do
    { status: 200,
      body: JSON.generate({ access_token: "valid_access_token", token_type: "Bearer" }),
      headers: { "Content-Type" => "application/json" } }
  end

  let(:valid_userinfo_response) do
    { status: 200,
      body: JSON.generate({ email: "admin@hatiwal.com", name: "Admin User", verified_email: true }),
      headers: { "Content-Type" => "application/json" } }
  end

  # Stub Rails credentials so specs don't need real encrypted credentials
  before do
    allow(Rails.application.credentials).to receive(:[]).and_call_original
    allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return("test-client-id")
    allow(Rails.application.credentials).to receive(:[]).with(:google_client_secret).and_return("test-client-secret")
  end

  # ── Initiate ────────────────────────────────────────────────────────────────
  describe "GET /admin/auth/google" do
    it "redirects to Google OAuth authorization URL" do
      get admin_google_auth_initiate_path
      expect(response).to redirect_to(%r{accounts\.google\.com/o/oauth2/auth})
    end

    it "includes required OAuth params in redirect URL" do
      get admin_google_auth_initiate_path
      redirect_uri = response.location
      expect(redirect_uri).to include("client_id=test-client-id")
      expect(redirect_uri).to include("response_type=code")
      expect(redirect_uri).to include("scope=")
      expect(redirect_uri).to include("state=")
    end

    it "stores state in session for CSRF protection" do
      get admin_google_auth_initiate_path
      expect(session[:google_oauth_state]).to be_present
    end

    context "when google_client_id is not in credentials" do
      before do
        allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(nil)
      end

      it "redirects to login with alert" do
        get admin_google_auth_initiate_path
        expect(response).to redirect_to(new_admin_user_session_path)
        expect(flash[:alert]).to include("not configured")
      end
    end
  end

  # ── Callback ────────────────────────────────────────────────────────────────
  describe "GET /admin/auth/google/callback" do
    before { get admin_google_auth_initiate_path }

    def valid_state
      session[:google_oauth_state]
    end

    context "with valid code and existing admin email" do
      before do
        stub_request(:post, "https://accounts.google.com/o/oauth2/token")
          .to_return(valid_token_response)
        stub_request(:get, "https://www.googleapis.com/oauth2/v2/userinfo")
          .to_return(valid_userinfo_response)
      end

      it "signs the admin in and redirects to admin root" do
        get admin_google_auth_callback_path, params: { code: "auth_code", state: valid_state }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:notice]).to include("Signed in")
      end
    end

    context "when email is not an admin" do
      before do
        stub_request(:post, "https://accounts.google.com/o/oauth2/token")
          .to_return(valid_token_response)
        stub_request(:get, "https://www.googleapis.com/oauth2/v2/userinfo")
          .to_return(status: 200,
                     body: JSON.generate({ email: "notanadmin@example.com", verified_email: true }),
                     headers: { "Content-Type" => "application/json" })
      end

      it "redirects to login with not-authorized alert" do
        get admin_google_auth_callback_path, params: { code: "auth_code", state: valid_state }
        expect(response).to redirect_to(new_admin_user_session_path)
        expect(flash[:alert]).to include("not authorized")
      end
    end

    context "when Google token exchange fails" do
      before do
        stub_request(:post, "https://accounts.google.com/o/oauth2/token")
          .to_return(status: 400,
                     body: JSON.generate({ error: "invalid_grant" }),
                     headers: { "Content-Type" => "application/json" })
      end

      it "redirects to login with error alert" do
        get admin_google_auth_callback_path, params: { code: "bad_code", state: valid_state }
        expect(response).to redirect_to(new_admin_user_session_path)
        expect(flash[:alert]).to include("Could not complete")
      end
    end

    context "when userinfo request fails" do
      before do
        stub_request(:post, "https://accounts.google.com/o/oauth2/token")
          .to_return(valid_token_response)
        stub_request(:get, "https://www.googleapis.com/oauth2/v2/userinfo")
          .to_return(status: 401, body: "", headers: {})
      end

      it "redirects to login with error alert" do
        get admin_google_auth_callback_path, params: { code: "auth_code", state: valid_state }
        expect(response).to redirect_to(new_admin_user_session_path)
        expect(flash[:alert]).to include("Could not complete")
      end
    end

    context "when state param is wrong (CSRF)" do
      it "redirects to login with CSRF alert" do
        get admin_google_auth_callback_path, params: { code: "auth_code", state: "tampered_state" }
        expect(response).to redirect_to(new_admin_user_session_path)
        expect(flash[:alert]).to include("Invalid OAuth state")
      end
    end

    context "when Google returns an error param" do
      it "redirects to login with cancelled alert" do
        get admin_google_auth_callback_path, params: { error: "access_denied", state: valid_state }
        expect(response).to redirect_to(new_admin_user_session_path)
        expect(flash[:alert]).to include("cancelled")
      end
    end
  end

  # ── Login page button ────────────────────────────────────────────────────────
  describe "GET /admin/login" do
    it "shows the Google sign-in button when client ID is in credentials" do
      get new_admin_user_session_path
      expect(response.body).to include("Sign in with Google")
      expect(response.body).to include(admin_google_auth_initiate_path)
    end

    context "when google_client_id is not in credentials" do
      before do
        allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(nil)
      end

      it "hides the Google sign-in button" do
        get new_admin_user_session_path
        expect(response.body).not_to include("Sign in with Google")
      end
    end
  end
end
