require "rails_helper"

# A push goes only to a device whose session is still alive (hatiwal-00's review of 28e1ac0, 2026-10-30): the
# token belongs to the devise client that registered it; once that session is gone — signed out elsewhere,
# revoked, expired — the token is cleared and nothing is sent. A stolen phone stops getting chat previews as
# soon as its session is revoked from the web. A token from before push_token_client (NULL) keeps today's rule.
RSpec.describe User, "#live_push_token" do
  let(:user) { create(:user) }
  let(:token) { "ExponentPushToken[phone]" }

  def session(client, expiry)
    user.update_columns(tokens: { client => { "token" => "digest", "expiry" => expiry } })
  end

  it "a live session's token is used" do
    session("phone-client", 1.week.from_now.to_i)
    user.update_columns(push_token: token, push_token_client: "phone-client")
    expect(user.live_push_token).to eq(token)
    expect(user.reload.push_token).to eq(token)
  end

  it "a session that is gone: nothing sent, the token cleared" do
    session("web-client", 1.week.from_now.to_i)
    user.update_columns(push_token: token, push_token_client: "phone-client")
    expect(user.live_push_token).to be_nil
    expect(user.reload.push_token).to be_nil
    expect(user.push_token_client).to be_nil
  end

  it "an expired session: nothing sent, the token cleared" do
    session("phone-client", 1.hour.ago.to_i)
    user.update_columns(push_token: token, push_token_client: "phone-client")
    expect(user.live_push_token).to be_nil
    expect(user.reload.push_token).to be_nil
  end

  it "a legacy token (no client recorded) keeps today's behaviour" do
    user.update_columns(push_token: token, push_token_client: nil, tokens: {})
    expect(user.live_push_token).to eq(token)
  end

  it "no token: nil" do
    expect(user.live_push_token).to be_nil
  end
end
