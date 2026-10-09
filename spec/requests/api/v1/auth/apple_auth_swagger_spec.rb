require "swagger_helper"

# RSwag documentation of POST /api/v1/auth/apple (behaviour: apple_auth_spec.rb).
RSpec.describe "Sign in with Apple", type: :request do
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:raw_nonce) { "swagger-nonce" }

  before do
    Rails.cache.delete(Apple::IdentityToken::JWKS_CACHE_KEY)
    stub_request(:get, Apple::IdentityToken::JWKS_URL)
      .to_return(status: 200, body: { keys: [ JWT::JWK.new(rsa, kid: "k1").export.merge(alg: "RS256") ] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def apple_token(nonce: raw_nonce)
    JWT.encode({ iss: "https://appleid.apple.com", aud: "com.hatiwal.app", sub: "001.swagger.1", email: "s@example.com",
                 email_verified: "true", nonce: Digest::SHA256.hexdigest(nonce), iat: Time.now.to_i,
                 exp: 5.minutes.from_now.to_i }, rsa, "RS256", { kid: "k1" })
  end

  path "/api/v1/auth/apple" do
    post "Sign in (or up) with Apple" do
      tags "Auth"
      description "Verifies Apple's identity token (JWKS, iss, aud = bundle id, exp, SHA-256 nonce), finds the " \
                  "person by Apple id, links a verified email, or creates the account; returns the same tokens " \
                  "as email sign-in (headers + body). iOS only for now."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[identity_token nonce],
        properties: {
          identity_token: { type: :string, description: "Apple's JWT" },
          nonce: { type: :string, description: "the RAW nonce (its SHA-256 was sent to Apple)" },
          authorization_code: { type: :string, description: "optional; kept only to revoke on account deletion" },
          given_name: { type: :string, description: "first sign-in only" },
          family_name: { type: :string, description: "first sign-in only" }
        }
      }

      response "200", "signed in (tokens in headers and body)" do
        let(:body) { { identity_token: apple_token, nonce: raw_nonce, given_name: "Ahmad", family_name: "Karimi" } }
        run_test! { |r| expect(JSON.parse(r.body)["access-token"]).to be_present }
      end

      response "401", "apple_token_invalid" do
        let(:body) { { identity_token: apple_token(nonce: "other"), nonce: raw_nonce } }
        run_test! { |r| expect(JSON.parse(r.body)["code"]).to eq("apple_token_invalid") }
      end

      response "422", "apple_token_missing" do
        let(:body) { { nonce: raw_nonce } }
        run_test! { |r| expect(JSON.parse(r.body)["code"]).to eq("apple_token_missing") }
      end
    end
  end
end
