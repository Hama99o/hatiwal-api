require "rails_helper"

# One device token = one account (hatiwal-00's review, 2026-10-30): on a shared phone A's session can end
# without a server sign-out (a 401 wipe, expiry, reinstall); when B signs in there and registers the SAME
# token, A's chat previews would go to the phone B holds. Registering a token takes it off every other user.
RSpec.describe "PUT /api/v1/users/me push_token — one account per device token", type: :request do
  let(:token) { "ExponentPushToken[shared-phone]" }
  let(:a) { create(:user, push_token: token, push_token_client: "a-client") }
  let(:b) { create(:user) }

  it "B registering A's token removes it from A" do
    a
    put "/api/v1/users/me", params: { user: { push_token: token } }, headers: auth_headers_for(b), as: :json
    expect(response).to have_http_status(:ok)
    expect(b.reload.push_token).to eq(token)
    expect(a.reload.push_token).to be_nil
    expect(a.push_token_client).to be_nil
  end

  it "another token leaves A alone" do
    a
    put "/api/v1/users/me", params: { user: { push_token: "ExponentPushToken[other]" } }, headers: auth_headers_for(b), as: :json
    expect(a.reload.push_token).to eq(token)
  end
end
