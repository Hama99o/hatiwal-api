require "rails_helper"

RSpec.describe "Api::V1::Auth::PasswordsController", type: :request do
  let(:user) { create(:user) }

  def generate_reset_token(for_user = user)
    raw, hashed = Devise.token_generator.generate(User, :reset_password_token)
    for_user.update!(
      reset_password_token: hashed,
      reset_password_sent_at: Time.now.utc,
      allow_password_change: true
    )
    raw
  end

  # ── POST /api/v1/auth/password — request reset ──────────────────────────────

  describe "POST /api/v1/auth/password — request reset" do
    it "returns 200 and enqueues a branded email for a known email" do
      expect do
        post "/api/v1/auth/password", params: { email: user.email }, as: :json
      end.to have_enqueued_mail(UserMailer, :reset_password)

      expect(response).to have_http_status(:ok)
    end

    it "persists the reset token and sent_at timestamp on the user" do
      post "/api/v1/auth/password", params: { email: user.email }, as: :json
      user.reload
      expect(user.reset_password_token).to be_present
      expect(user.reset_password_sent_at).to be_within(5.seconds).of(Time.now.utc)
    end

    it "returns 404 for an email that does not exist" do
      post "/api/v1/auth/password", params: { email: "nobody@nowhere.invalid" }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 when the email param is omitted (DTA convention)" do
      post "/api/v1/auth/password", params: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "is case-insensitive for the email lookup" do
      expect do
        post "/api/v1/auth/password", params: { email: user.email.upcase }, as: :json
      end.to have_enqueued_mail(UserMailer, :reset_password)

      expect(response).to have_http_status(:ok)
    end

    it "overwrites a previous reset token if the user requests again" do
      post "/api/v1/auth/password", params: { email: user.email }, as: :json
      first_token = user.reload.reset_password_token

      post "/api/v1/auth/password", params: { email: user.email }, as: :json
      second_token = user.reload.reset_password_token

      expect(second_token).not_to eq(first_token)
    end

    it "does not require authentication" do
      post "/api/v1/auth/password", params: { email: user.email }, as: :json
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # ── PUT /api/v1/auth/password — set new password ────────────────────────────

  describe "PUT /api/v1/auth/password — set new password" do
    context "with a valid token" do
      it "updates the password" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.valid_password?("newpassword123")).to be(true)
      end

      it "returns success JSON and the user data" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }, as: :json

        json = JSON.parse(response.body)
        expect(json["success"]).to be(true)
      end

      it "clears the reset token after use" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }, as: :json

        user.reload
        expect(user.reset_password_token).to be_nil
      end

      it "rejects the same token a second time" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }, as: :json
        expect(response).to have_http_status(:ok)

        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "anotherpassword",
          password_confirmation: "anotherpassword"
        }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an invalid token" do
      it "returns 401" do
        put "/api/v1/auth/password", params: {
          reset_password_token: "completely-wrong-token",
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an expired token" do
      it "returns 401" do
        raw_token = generate_reset_token
        user.update!(reset_password_sent_at: 7.hours.ago)

        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when passwords do not match" do
      it "returns 422" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "different_password"
        }, as: :json
        expect(response).not_to have_http_status(:ok)
      end
    end

    context "when password is too short" do
      it "returns an error" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token,
          password: "ab",
          password_confirmation: "ab"
        }, as: :json
        expect(response).not_to have_http_status(:ok)
      end
    end

    context "when password params are missing" do
      it "returns 422" do
        raw_token = generate_reset_token
        put "/api/v1/auth/password", params: {
          reset_password_token: raw_token
        }, as: :json
        expect(response).not_to have_http_status(:ok)
      end
    end
  end

  # ── UserMailer content ────────────────────────────────────────────────────────

  describe "UserMailer#reset_password" do
    it "uses the user's full name in the email body" do
      raw, hashed = Devise.token_generator.generate(User, :reset_password_token)
      user.update!(reset_password_token: hashed, reset_password_sent_at: Time.now.utc)

      mail = UserMailer.reset_password(user, raw)
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to include("Reset")
      expect(mail.body.encoded).to include(user.full_name)
    end

    it "includes a reset link with the raw token" do
      raw, hashed = Devise.token_generator.generate(User, :reset_password_token)
      user.update!(reset_password_token: hashed, reset_password_sent_at: Time.now.utc)

      mail = UserMailer.reset_password(user, raw)
      expect(mail.body.encoded).to include(raw)
    end
  end
end
