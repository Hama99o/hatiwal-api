require "rails_helper"

RSpec.describe "Api::V1::Auth::GoogleAuthController", type: :request do
  let(:google_email)      { "ahmad.karimi@gmail.com" }
  let(:google_sub)        { "1234567890" }
  let(:google_client_id)  { "test-client-id.apps.googleusercontent.com" }
  let(:google_ios_client_id) { "test-ios-client-id.apps.googleusercontent.com" }

  before do
    allow(Rails.application.credentials).to receive(:[]).and_call_original
    allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(google_client_id)
    allow(Rails.application.credentials).to receive(:[]).with(:google_ios_client_id).and_return(google_ios_client_id)
  end

  # Base valid payload — mirrors what Google's tokeninfo returns
  let(:valid_payload) do
    {
      "sub"            => google_sub,
      "email"          => google_email,
      "email_verified" => "true",
      "given_name"     => "Ahmad",
      "family_name"    => "Karimi",
      "picture"        => "https://lh3.googleusercontent.com/photo.jpg",
      "aud"            => google_client_id
    }.to_json
  end

  def stub_google(id_token:, status: 200, body: valid_payload)
    stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
      .with(query: { id_token: id_token })
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  describe "POST /api/v1/auth/google" do
    # ── Missing / malformed input ───────────────────────────────────────────────

    context "when id_token is missing" do
      it "returns 422" do
        post "/api/v1/auth/google", params: {}, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when Google returns a 400 (bad token)" do
      it "returns 401" do
        stub_google(id_token: "bad_token", status: 400, body: '{"error":"invalid_token"}')
        post "/api/v1/auth/google", params: { id_token: "bad_token" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when Google returns an expired token (400)" do
      it "returns 401" do
        stub_google(id_token: "expired_token", status: 400, body: '{"error":"Token has been expired or revoked."}')
        post "/api/v1/auth/google", params: { id_token: "expired_token" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when Google email is not verified" do
      it "returns 401" do
        unverified = { "sub" => "999", "email" => "user@gmail.com", "email_verified" => "false",
                       "given_name" => "X", "family_name" => "Y", "aud" => google_client_id }.to_json
        stub_google(id_token: "unverified_token", body: unverified)
        post "/api/v1/auth/google", params: { id_token: "unverified_token" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when Google payload has no email field" do
      it "returns 422" do
        no_email = { "sub" => "999", "email_verified" => "true", "aud" => google_client_id }.to_json
        stub_google(id_token: "no_email_token", body: no_email)
        post "/api/v1/auth/google", params: { id_token: "no_email_token" }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    # ── New user creation ───────────────────────────────────────────────────────

    context "with a valid token for a brand-new user" do
      before { stub_google(id_token: "new_user_token") }

      it "creates the user account" do
        expect do
          post "/api/v1/auth/google", params: { id_token: "new_user_token" }, as: :json
        end.to change(User, :count).by(1)

        user = User.find_by(email: google_email)
        expect(user.firstname).to eq("Ahmad")
        expect(user.lastname).to  eq("Karimi")
        expect(user.provider).to  eq("google")
        expect(user.status).to    eq("active")
      end

      it "returns auth tokens in the body" do
        post "/api/v1/auth/google", params: { id_token: "new_user_token" }, as: :json
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["access-token"]).to be_present
        expect(json["client"]).to       be_present
        expect(json["uid"]).to          eq(google_email)
        expect(json["expiry"]).to       be_present
        expect(json["token-type"]).to   eq("Bearer")
      end

      it "returns the user's profile in data" do
        post "/api/v1/auth/google", params: { id_token: "new_user_token" }, as: :json
        json = JSON.parse(response.body)
        expect(json["data"]["email"]).to     eq(google_email)
        expect(json["data"]["firstname"]).to eq("Ahmad")
      end

      it "returned tokens work for authenticated API requests" do
        post "/api/v1/auth/google", params: { id_token: "new_user_token" }, as: :json
        json = JSON.parse(response.body)

        get "/api/v1/auth/validate_token", headers: {
          "access-token" => json["access-token"],
          "client"       => json["client"],
          "uid"          => json["uid"]
        }, as: :json

        expect(response).to have_http_status(:ok)
      end

      it "email is case-insensitively normalized" do
        mixed_case = valid_payload.then { |p| JSON.parse(p).merge("email" => "Ahmad.Karimi@Gmail.COM").to_json }
        stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
          .with(query: { id_token: "mixed_case_token" })
          .to_return(status: 200, body: mixed_case, headers: { "Content-Type" => "application/json" })

        post "/api/v1/auth/google", params: { id_token: "mixed_case_token" }, as: :json
        expect(User.find_by(email: "ahmad.karimi@gmail.com")).to be_present
      end
    end

    # ── Existing user sign-in ───────────────────────────────────────────────────

    context "with a valid token matching an existing email-provider user" do
      let!(:existing_user) { create(:user, email: google_email, provider: "email") }

      before { stub_google(id_token: "existing_user_token") }

      it "does NOT create a duplicate user" do
        expect do
          post "/api/v1/auth/google", params: { id_token: "existing_user_token" }, as: :json
        end.not_to change(User, :count)
      end

      it "signs in the existing user" do
        post "/api/v1/auth/google", params: { id_token: "existing_user_token" }, as: :json
        json = JSON.parse(response.body)
        expect(json["uid"]).to eq(google_email)
      end

      it "does NOT change the existing user's provider (preserves email login)" do
        post "/api/v1/auth/google", params: { id_token: "existing_user_token" }, as: :json
        expect(existing_user.reload.provider).to eq("email")
      end
    end

    context "with a valid token for an existing Google user signing in again" do
      let!(:google_user) { create(:user, email: google_email, uid: google_email, provider: "google") }

      before { stub_google(id_token: "returning_google_token") }

      it "signs in without creating a duplicate" do
        expect do
          post "/api/v1/auth/google", params: { id_token: "returning_google_token" }, as: :json
        end.not_to change(User, :count)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["uid"]).to eq(google_email)
      end
    end

    # ── Account status guards ────────────────────────────────────────────────────

    context "when the user account is suspended" do
      let!(:suspended_user) { create(:user, email: google_email, status: :suspended) }

      before { stub_google(id_token: "suspended_token") }

      it "returns 403 Forbidden" do
        post "/api/v1/auth/google", params: { id_token: "suspended_token" }, as: :json
        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["error"]).to match(/account_suspended/)
      end
    end

    context "when the user account is banned" do
      let!(:banned_user) { create(:user, email: google_email, status: :banned) }

      before { stub_google(id_token: "banned_token") }

      it "returns 403 Forbidden" do
        post "/api/v1/auth/google", params: { id_token: "banned_token" }, as: :json
        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["error"]).to match(/account_banned/)
      end
    end

    context "when the user account is permanently deleted" do
      let!(:deleted_user) { create(:user, email: google_email, deleted_at: 1.day.ago) }

      before { stub_google(id_token: "deleted_token") }

      it "returns 403 Forbidden with account_deleted error key" do
        post "/api/v1/auth/google", params: { id_token: "deleted_token" }, as: :json
        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("account_deleted")
      end
    end

    # ── iOS OAuth client token (aud = iOS client ID) ────────────────────────────

    context "with a valid token from the iOS OAuth client" do
      let(:ios_payload) do
        {
          "sub"            => google_sub,
          "email"          => google_email,
          "email_verified" => "true",
          "given_name"     => "Ahmad",
          "family_name"    => "Karimi",
          "aud"            => google_ios_client_id
        }.to_json
      end

      before do
        stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
          .with(query: { id_token: "ios_token" })
          .to_return(status: 200, body: ios_payload, headers: { "Content-Type" => "application/json" })
      end

      it "accepts the iOS client audience and signs in" do
        post "/api/v1/auth/google", params: { id_token: "ios_token" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["uid"]).to eq(google_email)
      end
    end

    context "with a token from an unknown audience" do
      let(:wrong_aud_payload) do
        { "sub" => "x", "email" => "x@gmail.com", "email_verified" => "true",
          "aud" => "unknown-client.apps.googleusercontent.com" }.to_json
      end

      before do
        stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
          .with(query: { id_token: "wrong_aud_token" })
          .to_return(status: 200, body: wrong_aud_payload, headers: { "Content-Type" => "application/json" })
      end

      it "returns 401" do
        post "/api/v1/auth/google", params: { id_token: "wrong_aud_token" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    # ── Google returns partial name data ─────────────────────────────────────────

    context "when Google payload has no given_name or family_name" do
      before do
        no_name = {
          "sub" => "111", "email" => "noname@gmail.com",
          "email_verified" => "true", "aud" => google_client_id
        }.to_json
        stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
          .with(query: { id_token: "no_name_token" })
          .to_return(status: 200, body: no_name, headers: { "Content-Type" => "application/json" })
      end

      it "creates user with safe defaults" do
        post "/api/v1/auth/google", params: { id_token: "no_name_token" }, as: :json
        expect(response).to have_http_status(:ok)
        user = User.find_by(email: "noname@gmail.com")
        expect(user.firstname).to eq("User")
        expect(user.lastname).to  eq(".")
      end
    end
  end
end
