require "rails_helper"

# The push token belongs to the device (devise client) that registered it. A sign-out clears it only when
# THAT client signs out: a sign-out on the web, or on another phone, used to wipe the phone's token too, and
# the phone stopped getting chat pushes with no sign of it (found by QA B11 E, 2026-10-29: the rig's API
# sessions as the seller signed out and cleared the phone's token each time).
RSpec.describe "Push token on sign-out", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password, password_confirmation: password, confirmed_at: 1.day.ago) }
  let(:token) { "ExponentPushToken[phone-1]" }

  def sign_in_client
    post "/api/v1/auth/sign_in", params: { email: user.email, password: password }, as: :json
    %w[access-token client uid token-type].index_with { |h| response.headers[h] }
  end

  def register(headers, push_token = token)
    put "/api/v1/users/me", params: { user: { push_token: push_token } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  def sign_out(headers)
    delete "/api/v1/auth/sign_out", headers: headers
  end

  it "stores which client registered the token" do
    phone = sign_in_client
    register(phone)
    expect(user.reload.push_token).to eq(token)
    expect(user.push_token_client).to eq(phone["client"])
  end

  it "a sign-out on the web keeps the phone's token" do
    phone = sign_in_client
    register(phone)
    web = sign_in_client
    sign_out(web)
    expect(response).to have_http_status(:ok)
    expect(user.reload.push_token).to eq(token)
  end

  it "another phone's sign-out keeps it" do
    phone = sign_in_client
    register(phone)
    other_phone = sign_in_client # notifications refused there: it never registered a token
    sign_out(other_phone)
    expect(user.reload.push_token).to eq(token)
    expect(user.push_token_client).to eq(phone["client"])
  end

  it "the phone's own sign-out clears it" do
    phone = sign_in_client
    register(phone)
    sign_out(phone)
    expect(user.reload.push_token).to be_nil
    expect(user.push_token_client).to be_nil
  end

  it "a legacy token (registered before the client was recorded) keeps today's behaviour: cleared on a sign-out" do
    user.update_columns(push_token: token, push_token_client: nil)
    sign_out(sign_in_client)
    expect(user.reload.push_token).to be_nil
  end
end
