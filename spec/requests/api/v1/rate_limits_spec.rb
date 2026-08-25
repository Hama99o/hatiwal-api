require "rails_helper"

# Nothing bounded any endpoint before RateLimitable: signup, login, password
# reset, listing creation, conversations, messages and reports were all
# unlimited, so one script could farm accounts or bury the buyer feed.
#
# These examples pin the two things that actually have to hold: the limit fires
# at all (it silently would not, on a cache store whose #increment returns nil),
# and a per-user limit belongs to that ONE user rather than to everybody.
RSpec.describe "Rate limiting", type: :request do
  describe "signup, keyed by IP" do
    def sign_up(n)
      post "/api/v1/auth",
           params: {
             email: "farmed#{n}@example.com",
             password: "Password123!",
             password_confirmation: "Password123!",
             firstname: "Account",
             lastname:  "Number#{n}"
           },
           as: :json
    end

    it "refuses the 11th signup from one address within the hour" do
      10.times { |i| sign_up(i) }
      expect(response).to have_http_status(:ok)

      sign_up(:eleventh)

      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)["error"]).to eq("rate_limited")
    end
  end

  # A limiter must never be the reason a request fails. This concern is the first
  # thing in the app to touch Rails.cache, so a cache outage went from completely
  # harmless to potentially fatal for sign-in — it has to fail open instead.
  describe "when the cache store backing the limits is unreachable" do
    it "lets the request through rather than 500ing the endpoint" do
      allow(RateLimitable.store).to receive(:increment).and_raise(Errno::ECONNREFUSED)

      post "/api/v1/auth",
           params: {
             email: "during-an-outage@example.com", password: "Password123!",
             password_confirmation: "Password123!", firstname: "Cache", lastname: "Down"
           },
           as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe "listing creation, keyed by user" do
    let(:category) { create(:category) }

    def create_listing(headers)
      post "/api/v1/my/listings",
           params:  { listing: attributes_for(:listing).merge(category_id: category.id) },
           headers: headers,
           as:      :json
    end

    it "cuts off the flooding seller at the daily limit" do
      headers = auth_headers_for(create(:user))
      30.times { create_listing(headers) }
      expect(response).to have_http_status(:created)

      create_listing(headers)

      expect(response).to have_http_status(:too_many_requests)
    end

    it "does not spend anybody else's quota" do
      flooder = auth_headers_for(create(:user))
      31.times { create_listing(flooder) }
      expect(response).to have_http_status(:too_many_requests)

      create_listing(auth_headers_for(create(:user)))

      expect(response).to have_http_status(:created)
    end
  end
end
