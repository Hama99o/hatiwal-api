require "rails_helper"

# Owner rule 2026-10-12: Sign in with Apple does not ship until the Apple
# console setup is done. Until APPLE_SIGN_IN_ENABLED is set, POST /auth/apple
# answers 404 as if it did not exist, before it reads the token or reaches Apple.
RSpec.describe "Sign in with Apple behind APPLE_SIGN_IN_ENABLED", type: :request do
  around do |example|
    before = ENV.fetch("APPLE_SIGN_IN_ENABLED", nil)
    example.run
  ensure
    ENV["APPLE_SIGN_IN_ENABLED"] = before
  end

  it "is a 404 while the flag is unset (the default)" do
    ENV.delete("APPLE_SIGN_IN_ENABLED")
    post "/api/v1/auth/apple", params: { identity_token: "anything", nonce: "n" }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(WebMock).not_to have_requested(:get, Apple::IdentityToken::JWKS_URL)
  end

  it "is a 404 when the flag is set to a false value" do
    ENV["APPLE_SIGN_IN_ENABLED"] = "false"
    post "/api/v1/auth/apple", params: { identity_token: "anything" }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "answers when the flag is on" do
    ENV["APPLE_SIGN_IN_ENABLED"] = "true"
    post "/api/v1/auth/apple", params: {}, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("apple_token_missing")
  end
end
