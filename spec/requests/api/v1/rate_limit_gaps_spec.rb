require "rails_helper"

# Hunt-2 (1.1.7): the write endpoints RateLimitable had not reached yet. Each
# limit is far above human use and keyed by the signed-in user, except the
# password reset, which is now ALSO limited per email address: the IP limit
# alone let a botnet (or a whole city behind one carrier NAT, in reverse) send
# one person reset emails without end.
#
# The limiter runs before the action, so the requests need not succeed to count:
# these use ids that do not exist and only check that the (n+1)th is a 429.
RSpec.describe "Rate limits on the remaining write endpoints", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def expect_limit(limit)
    limit.times do |i|
      yield i
      expect(response).not_to have_http_status(:too_many_requests), "request #{i + 1} of #{limit} was limited"
    end
    yield limit
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["error"]).to eq("rate_limited")
  end

  it "opening the Support thread: 60 an hour" do
    expect_limit(60) { post "/api/v1/support_conversation", headers: headers }
  end

  it "writing or editing reviews: 60 a day" do
    expect_limit(60) { |i| i.even? ? post("/api/v1/transactions/0/reviews", headers: headers) : patch("/api/v1/reviews/0", headers: headers) }
  end

  it "blocking and unblocking people: 60 an hour" do
    expect_limit(60) { |i| i.even? ? post("/api/v1/users/0/block", headers: headers) : delete("/api/v1/users/0/block", headers: headers) }
  end

  it "blocking and unblocking shops: 60 an hour" do
    expect_limit(60) { |i| i.even? ? post("/api/v1/shops/0/block", headers: headers) : delete("/api/v1/shops/0/block", headers: headers) }
  end

  it "profile updates: 120 an hour" do
    expect_limit(120) { patch "/api/v1/users/me", params: { user: { bio: "x" } }, headers: headers, as: :json }
  end

  it "shop updates: 60 an hour" do
    shop = create(:shop, owner: user) # set_shop runs first: an unknown id 404s before the limit
    expect_limit(60) { patch "/api/v1/shops/#{shop.id}", params: { shop: { description: "x" } }, headers: headers, as: :json }
  end

  it "the limits are per user: another account is unaffected" do
    60.times { post "/api/v1/users/0/block", headers: headers }
    post "/api/v1/users/0/block", headers: auth_headers_for(create(:user))
    expect(response).not_to have_http_status(:too_many_requests)
  end

  describe "password reset emails" do
    def reset(email, ip)
      post "/api/v1/auth/password", params: { email: email }, headers: { "REMOTE_ADDR" => ip }, as: :json
    end

    it "3 an hour per email address, whatever the IP" do
      expect_limit(3) { |i| reset("Target@Example.com ", "10.0.0.#{i + 1}") }
    end

    it "another address still gets its email" do
      3.times { |i| reset("target@example.com", "10.0.1.#{i + 1}") }
      reset("someone.else@example.com", "10.0.1.9")
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
