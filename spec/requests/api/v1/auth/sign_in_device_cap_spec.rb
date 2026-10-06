require "rails_helper"

# P0 (d0 run-233, 2026-10-06): an isolated sign-in answered 200 with NO auth
# headers, and users lost stored tokens without signing out.
#
# devise_token_auth's clean_old_tokens runs once a user has more than
# max_number_of_devices (10) tokens. It first drops every token whose expiry is
# later than `now + token_lifespan.to_i`. With token_lifespan = 2.months that
# limit is 60.87 days (2.months.to_i), but a NEW token's expiry is
# `now + 2.months` in CALENDAR months (Oct 6 → Dec 6 = 61 days). So the token
# being created was always "too far" and removed in the same save: 200, no
# headers, no session. A fixed-length lifespan keeps both sides equal.
RSpec.describe "Signing in with more than 10 device tokens", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def sign_in
    post "/api/v1/auth/sign_in", params: { email: user.email, password: "password123" }, as: :json
    response.headers.slice("access-token", "client", "uid")
  end

  # A 61-day span (October → December): the case that broke.
  around { |example| travel_to(Time.utc(2026, 10, 6, 19, 59)) { example.run } }

  it "the 11th and later sign-ins still return working headers, and the device cap still holds" do
    13.times do |i|
      headers = sign_in
      expect(response).to have_http_status(:ok)
      expect(headers.compact_blank.keys).to match_array(%w[access-token client uid]), "sign-in ##{i + 1} came back without auth headers"
      expect(user.reload.tokens).to have_key(headers["client"])
    end
    expect(user.reload.tokens.size).to eq(DeviseTokenAuth.max_number_of_devices)

    get "/api/v1/users/me", headers: sign_in
    expect(response).to have_http_status(:ok)
  end

  # Tokens issued BEFORE the fix carry a calendar 61-day expiry, later than
  # `now + token_lifespan.to_i`. Right after a deploy, an 11th sign-in must
  # still keep the newest 10, the new one included, and drop only the oldest.
  it "with 10 pre-fix (61-day) tokens, an 11th sign-in keeps the new one and the 9 newest" do
    oldest = nil
    10.times do |i|
      issued = Time.current - (10 - i).minutes
      client = "prefix-#{i}"
      oldest ||= client
      user.tokens[client] = { "token" => BCrypt::Password.create("t#{i}", cost: 4), "expiry" => (issued + 2.months).to_i }
    end
    user.save!

    headers = sign_in
    expect(response).to have_http_status(:ok)
    expect(headers.compact_blank.keys).to match_array(%w[access-token client uid])
    tokens = user.reload.tokens
    expect(tokens.size).to eq(10)
    expect(tokens).to have_key(headers["client"])
    expect(tokens).not_to have_key(oldest)
    expect(tokens.keys - [ headers["client"] ]).to match_array((1..9).map { |i| "prefix-#{i}" })
  end

  it "a token issued for an existing client (re-issue) is kept too" do
    11.times { user.create_token }
    client = user.tokens.keys.first
    user.create_token(client: client)
    expect(user.tokens).to have_key(client)
    expect(user.tokens.size).to eq(10)
  end

  it "the session keep-alive and a new token use the same lifespan as the cleanup limit" do
    token = user.create_token
    expect(token.expiry).to be <= Time.now.to_i + DeviseTokenAuth.token_lifespan.to_i
  end
end
