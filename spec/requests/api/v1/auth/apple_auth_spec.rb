require "rails_helper"

# Sign in with Apple (1.1.7, iOS first). The app sends Apple's identity token
# (a JWT signed by Apple), the RAW nonce it hashed into the request, the one-time
# authorization code, and — first sign-in only — the name Apple gave it.
# Tokens here are signed with a test RSA key served as Apple's JWKS.
RSpec.describe "Api::V1::Auth::AppleAuthController", type: :request do
  include ActiveJob::TestHelper

  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "test-apple-kid" }
  let(:raw_nonce) { "raw-nonce-#{SecureRandom.hex(8)}" }
  let(:sub) { "001234.abcdef0123456789.0123" }
  let(:email) { "ahmad@example.com" }

  before do
    Rails.cache.delete(Apple::IdentityToken::JWKS_CACHE_KEY)
    jwks = { keys: [ JWT::JWK.new(rsa, kid: kid).export.merge(alg: "RS256", use: "sig") ] }
    stub_request(:get, Apple::IdentityToken::JWKS_URL).to_return(status: 200, body: jwks.to_json,
                                                                  headers: { "Content-Type" => "application/json" })
  end

  def identity_token(key: rsa, **over)
    claims = { iss: "https://appleid.apple.com", aud: "com.hatiwal.app", sub: sub, email: email,
               email_verified: "true", nonce: Digest::SHA256.hexdigest(raw_nonce),
               iat: Time.now.to_i, exp: 10.minutes.from_now.to_i }.merge(over).compact
    JWT.encode(claims, key, "RS256", { kid: kid })
  end

  def sign_in_apple(token: identity_token, nonce: raw_nonce, **extra)
    post "/api/v1/auth/apple", params: { identity_token: token, nonce: nonce, **extra }, as: :json
  end

  def json = JSON.parse(response.body)

  describe "rejections" do
    it "422 apple_token_missing without an identity token" do
      post "/api/v1/auth/apple", params: { nonce: raw_nonce }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["code"]).to eq("apple_token_missing")
    end

    {
      "a token signed by another key" => -> { { token: identity_token(key: OpenSSL::PKey::RSA.generate(2048)) } },
      "another issuer" => -> { { token: identity_token(iss: "https://evil.example") } },
      "another audience (an app that is not ours)" => -> { { token: identity_token(aud: "com.other.app") } },
      "an expired token" => -> { { token: identity_token(iat: 2.hours.ago.to_i, exp: 1.hour.ago.to_i) } },
      "a nonce that does not match" => -> { { nonce: "some-other-nonce" } },
      "no nonce at all" => -> { { nonce: nil } },
      "garbage" => -> { { token: "not.a.jwt" } }
    }.each do |label, args|
      it "401 apple_token_invalid for #{label}, and creates no user" do
        expect { sign_in_apple(**instance_exec(&args)) }.not_to change(User, :count)
        expect(response).to have_http_status(:unauthorized)
        expect(json["code"]).to eq("apple_token_invalid")
      end
    end
  end

  describe "a new person" do
    it "creates the account from the token + the first-sign-in name, signs it in like sign_in" do
      expect { sign_in_apple(given_name: "Ahmad", family_name: "Karimi") }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      user = User.find_by(apple_uid: sub)
      expect(user).to have_attributes(email: email, uid: email, provider: "apple", firstname: "Ahmad", lastname: "Karimi")
      expect(user.confirmed_at).to be_present # Apple verified the address
      expect(json["data"]["id"]).to eq(user.id)
      # Same token contract as sign_in: headers AND (like Google) the body.
      %w[access-token client uid].each { |h| expect(response.headers[h]).to be_present }
      expect(json["access-token"]).to eq(response.headers["access-token"])
      expect(json["client"]).to eq(response.headers["client"])
      get "/api/v1/users/me", headers: response.headers.slice("access-token", "client", "uid", "token-type")
      expect(response).to have_http_status(:ok)
    end

    it "accepts Apple's private relay address (Hide My Email)" do
      relay = "x7y2kq9p@privaterelay.appleid.com"
      sign_in_apple(token: identity_token(email: relay, is_private_email: "true"))
      expect(response).to have_http_status(:ok)
      expect(User.find_by(apple_uid: sub).email).to eq(relay)
    end

    it "falls back to a neutral name when Apple sent none" do
      sign_in_apple
      expect(User.find_by(apple_uid: sub)).to have_attributes(firstname: "User", lastname: ".")
    end

    it "422 apple_email_missing when the token carries no email and no account has this Apple id" do
      sign_in_apple(token: identity_token(email: nil, email_verified: nil))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["code"]).to eq("apple_email_missing")
    end
  end

  describe "a returning person" do
    let!(:user) { create(:user, :confirmed, email: email, uid: email, apple_uid: sub, provider: "apple") }

    it "is found by the Apple id, even without email or name on later sign-ins" do
      expect { sign_in_apple(token: identity_token(email: nil, email_verified: nil)) }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
      expect(json["data"]["id"]).to eq(user.id)
      expect(user.reload.firstname).not_to eq("User") # a later sign-in never renames them
    end

    it "is refused when the account is blocked, like email login" do
      user.update_columns(status: User.statuses[:suspended])
      sign_in_apple
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "an existing email account" do
    let!(:existing) { create(:user, :confirmed, email: email) }

    it "is LINKED (no second account) when Apple says the email is verified" do
      expect { sign_in_apple }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
      expect(existing.reload.apple_uid).to eq(sub)
      expect(json["data"]["id"]).to eq(existing.id)
    end

    it "is NOT linked on an unverified email: 409 apple_email_unverified, nothing created" do
      expect { sign_in_apple(token: identity_token(email_verified: "false")) }.not_to change(User, :count)
      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("apple_email_unverified")
      expect(existing.reload.apple_uid).to be_nil
    end
  end

  # d0 security review 2026-10-09 — PRE-HIJACKING: anyone can register someone
  # else's address by email + password and simply never confirm it. When the
  # real owner then signs in with Apple (Apple verified that address), the Apple
  # id was linked onto the squatter's account, and the squatter's password and
  # sessions kept working on the owner's account. Linking to an UNCONFIRMED
  # account now confirms it, replaces the password and ends every other session.
  describe "an UNCONFIRMED account with the same email (possibly a squatter's)" do
    let!(:squatter) { create(:user, email: email, password: "squatter-pass-1", password_confirmation: "squatter-pass-1", confirmed_at: nil) }

    it "is linked, but the squatter's password and sessions stop working" do
      old_headers = auth_headers_for(squatter)
      sign_in_apple
      expect(response).to have_http_status(:ok)
      expect(squatter.reload.apple_uid).to eq(sub)
      expect(squatter.confirmed_at).to be_present

      get "/api/v1/users/me", headers: old_headers
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/auth/sign_in", params: { email: email, password: "squatter-pass-1" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "the authorization code (kept only to revoke on deletion)" do
    let(:configured) do
      { team_id: "TEAM123456", key_id: "KEY1234567", client_id: "com.hatiwal.app",
        private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem }
    end

    it "is exchanged for a refresh token, stored ENCRYPTED, when the Apple key is configured" do
      allow(Apple::Config).to receive(:settings).and_return(configured)
      token_call = stub_request(:post, Apple::Tokens::TOKEN_URL)
                   .with(body: hash_including("code" => "auth-code-1", "grant_type" => "authorization_code",
                                              "client_id" => "com.hatiwal.app"))
                   .to_return(status: 200, body: { refresh_token: "r-tok-1" }.to_json,
                              headers: { "Content-Type" => "application/json" })
      sign_in_apple(authorization_code: "auth-code-1")
      expect(token_call).to have_been_requested
      user = User.find_by(apple_uid: sub)
      expect(user.apple_refresh_token).to eq("r-tok-1")
      raw = User.connection.select_value("SELECT apple_refresh_token FROM users WHERE id = #{user.id}")
      expect(raw).not_to include("r-tok-1")
    end

    it "is ignored (sign-in still works, a warning logged) when the Apple key is not configured" do
      allow(Apple::Config).to receive(:settings).and_return({})
      expect(Rails.logger).to receive(:warn).with(/Sign in with Apple.*not configured/).at_least(:once)
      sign_in_apple(authorization_code: "auth-code-1")
      expect(response).to have_http_status(:ok)
      expect(a_request(:post, Apple::Tokens::TOKEN_URL)).not_to have_been_made
    end
  end
end
