require "rails_helper"

# devise_token_auth renders its OWN user payload (User#token_validation_response),
# not UserSerializer. The apps gate "Open your shop" and Verify on
# `email_confirmed` from whichever payload they last stored — sign_in and
# validate_token included — so it has to be there too (device check
# 2026-10-07: an unconfirmed account skipped the gate after signing in).
RSpec.describe "email_confirmed on devise_token_auth payloads", type: :request do
  let(:password) { "Password123!" }

  def sign_in(user)
    post "/api/v1/auth/sign_in", params: { email: user.email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
    response
  end

  it "sign_in says false for an unconfirmed account and true for a confirmed one" do
    unconfirmed = create(:user, password: password, password_confirmation: password, confirmed_at: nil)
    expect(JSON.parse(sign_in(unconfirmed).body)["data"]["email_confirmed"]).to be(false)

    confirmed = create(:user, password: password, password_confirmation: password, confirmed_at: 1.day.ago)
    expect(JSON.parse(sign_in(confirmed).body)["data"]["email_confirmed"]).to be(true)
  end

  it "validate_token carries it too (the app's reload path)" do
    user = create(:user, password: password, password_confirmation: password, confirmed_at: nil)
    headers = sign_in(user).headers.slice("access-token", "client", "uid", "token-type", "expiry")

    get "/api/v1/auth/validate_token", headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["email_confirmed"]).to be(false)
  end
end
