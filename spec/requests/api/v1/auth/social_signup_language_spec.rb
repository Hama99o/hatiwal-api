require "rails_helper"

# A NEW account made by Google or Apple sign-in takes the language the app was in
# (`preferred_language`). The column defaults to "ps", so without it someone who
# used the app in English landed on a Pashto, right-to-left app the moment the
# account was created (device test 2026-10-29, docs/qa-1.2.0/google-signin in the
# mobile repo). Email sign-up already sent it. The language is used on CREATE only:
# a returning person keeps the one they chose.
RSpec.describe "Social sign-up language", type: :request do
  let(:default_language) { User.column_defaults["preferred_language"] }

  describe "POST /api/v1/auth/google" do
    let(:google_client_id) { "test-client-id.apps.googleusercontent.com" }
    let(:google_email) { "new.person@gmail.com" }

    before do
      allow(Rails.application.credentials).to receive(:[]).and_call_original
      allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(google_client_id)
      stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
        .with(query: { id_token: "tok" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { sub: "42", email: google_email, email_verified: "true", given_name: "New",
                           family_name: "Person", aud: google_client_id }.to_json)
    end

    def sign_in_google(**extra)
      post "/api/v1/auth/google", params: { id_token: "tok", **extra }, as: :json
    end

    it "gives a new account the app's language" do
      sign_in_google(preferred_language: "en")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email: google_email).preferred_language).to eq("en")
      expect(response.parsed_body.dig("data", "preferred_language") || response.parsed_body.dig("data", "preferredLanguage")).to eq("en")
    end

    it "takes every supported language" do
      sign_in_google(preferred_language: "ur")
      expect(User.find_by(email: google_email).preferred_language).to eq("ur")
    end

    it "falls back to the default for an unknown language, and still signs in" do
      sign_in_google(preferred_language: "xx")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email: google_email).preferred_language).to eq(default_language)
    end

    it "keeps the default when the app sends none (older apps)" do
      sign_in_google
      expect(User.find_by(email: google_email).preferred_language).to eq(default_language)
    end

    it "never changes a returning person's language" do
      create(:user, email: google_email, uid: google_email, provider: "google", preferred_language: "fa",
                    confirmed_at: 1.day.ago)
      sign_in_google(preferred_language: "en")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email: google_email).preferred_language).to eq("fa")
    end
  end

  describe "POST /api/v1/auth/apple" do
    let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
    let(:kid) { "test-apple-kid" }
    let(:raw_nonce) { "raw-nonce-#{SecureRandom.hex(8)}" }
    let(:sub) { "001234.lang0123456789.0123" }
    let(:apple_email) { "new.apple@example.com" }

    before do
      allow(Api::V1::Auth::AppleAuthController).to receive(:enabled?).and_return(true)
      Rails.cache.delete(Apple::IdentityToken::JWKS_CACHE_KEY)
      jwks = { keys: [ JWT::JWK.new(rsa, kid: kid).export.merge(alg: "RS256", use: "sig") ] }
      stub_request(:get, Apple::IdentityToken::JWKS_URL).to_return(status: 200, body: jwks.to_json,
                                                                    headers: { "Content-Type" => "application/json" })
    end

    def sign_in_apple(**extra)
      claims = { iss: "https://appleid.apple.com", aud: "com.hatiwal.app", sub: sub, email: apple_email,
                 email_verified: "true", nonce: Digest::SHA256.hexdigest(raw_nonce),
                 iat: Time.now.to_i, exp: 10.minutes.from_now.to_i }
      token = JWT.encode(claims, rsa, "RS256", { kid: kid })
      post "/api/v1/auth/apple", params: { identity_token: token, nonce: raw_nonce, **extra }, as: :json
    end

    it "gives a new account the app's language" do
      sign_in_apple(preferred_language: "en")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(apple_uid: sub).preferred_language).to eq("en")
    end

    it "falls back to the default for an unknown language, and still signs in" do
      sign_in_apple(preferred_language: "xx")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(apple_uid: sub).preferred_language).to eq(default_language)
    end

    it "keeps the default when the app sends none (older apps)" do
      sign_in_apple
      expect(User.find_by(apple_uid: sub).preferred_language).to eq(default_language)
    end

    it "never changes a returning person's language" do
      create(:user, email: apple_email, uid: apple_email, provider: "apple", apple_uid: sub,
                    preferred_language: "fa", confirmed_at: 1.day.ago)
      sign_in_apple(preferred_language: "en")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(apple_uid: sub).preferred_language).to eq("fa")
    end

    it "never changes the language of an email account it links to" do
      create(:user, email: apple_email, uid: apple_email, preferred_language: "fa", confirmed_at: 1.day.ago)
      sign_in_apple(preferred_language: "en")
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email: apple_email).preferred_language).to eq("fa")
    end
  end
end
