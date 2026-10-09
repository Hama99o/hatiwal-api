require "rails_helper"

# Production 2026-10-09: GET /listings with a radius AND seller_active_days
# answered 500 ("column reference latitude is ambiguous"): the seller filter
# joins users, which also has latitude/longitude (guessed location), and the
# Haversine SQL used bare column names.
RSpec.describe "GET /api/v1/listings radius + seller filter", type: :request do
  let(:seller) { create(:user, last_sign_in_at: 1.day.ago) }
  let!(:near) { create(:listing, user: seller, status: :active, latitude: 34.5553, longitude: 69.2075) }

  before { seller.update_columns(latitude: 34.0, longitude: 69.0) if seller.has_attribute?(:latitude) }

  it "answers 200 and keeps the nearby listing" do
    get "/api/v1/listings", params: {
      latitude: 34.5553, longitude: 69.2075, radius: 5, sort: "price_asc", seller_active_days: 7
    }
    expect(response).to have_http_status(:ok)
  end
end
