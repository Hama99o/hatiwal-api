require "rails_helper"

# Focused tests for the Browse filters: price range, free-text location,
# and coordinate + radius (Haversine distance) filtering.
RSpec.describe "Api::V1::Listings filtering", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  # Kabul city center
  let(:kabul_lat) { 34.5553 }
  let(:kabul_lng) { 69.2075 }

  def titles
    JSON.parse(response.body)["listings"].map { |l| l["title"] }
  end

  describe "expiry" do
    it "hides expired listings from the buyer feed" do
      create(:listing, :active, title: "Fresh", expires_at: 5.days.from_now)
      create(:listing, :active, title: "Stale", expires_at: 1.day.ago)
      create(:listing, :active, title: "NoExpiry", expires_at: nil)

      get "/api/v1/listings", headers: headers

      expect(titles).to contain_exactly("Fresh", "NoExpiry")
    end
  end

  describe "price filtering" do
    before do
      create(:listing, :active, title: "Cheap", price: 500)
      create(:listing, :active, title: "Mid", price: 5_000)
      create(:listing, :active, title: "Pricey", price: 50_000)
    end

    it "filters by minimum price" do
      get "/api/v1/listings", params: { price_min: 4_000 }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(titles).to contain_exactly("Mid", "Pricey")
    end

    it "filters by maximum price" do
      get "/api/v1/listings", params: { price_max: 4_000 }, headers: headers
      expect(titles).to contain_exactly("Cheap")
    end

    it "filters by a price range" do
      get "/api/v1/listings", params: { price_min: 1_000, price_max: 10_000 }, headers: headers
      expect(titles).to contain_exactly("Mid")
    end
  end

  describe "free-text location filtering" do
    before do
      create(:listing, :active, title: "In Kabul",    location: "Kabul, Afghanistan")
      create(:listing, :active, title: "In Herat",     location: "Herat")
    end

    it "matches case-insensitively on location substring" do
      get "/api/v1/listings", params: { location: "kabul" }, headers: headers
      expect(titles).to contain_exactly("In Kabul")
    end
  end

  describe "coordinate + radius (distance) filtering" do
    before do
      # ~3 km north of Kabul center
      create(:listing, :active, title: "Near", latitude: 34.5800, longitude: 69.2100)
      # Herat — ~570 km from Kabul
      create(:listing, :active, title: "Far",  latitude: 34.3529, longitude: 62.2040)
      # No coordinates at all
      create(:listing, :active, title: "NoCoords", latitude: nil, longitude: nil)
    end

    it "returns only listings within the radius" do
      get "/api/v1/listings",
          params: { latitude: kabul_lat, longitude: kabul_lng, radius: 10 },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(titles).to contain_exactly("Near")
    end

    it "widens results as the radius grows" do
      get "/api/v1/listings",
          params: { latitude: kabul_lat, longitude: kabul_lng, radius: 1000 },
          headers: headers

      expect(titles).to contain_exactly("Near", "Far")
    end

    it "excludes listings without coordinates" do
      get "/api/v1/listings",
          params: { latitude: kabul_lat, longitude: kabul_lng, radius: 10 },
          headers: headers

      expect(titles).not_to include("NoCoords")
    end

    it "prefers coordinates over free-text location when both are present" do
      get "/api/v1/listings",
          params: { latitude: kabul_lat, longitude: kabul_lng, radius: 10, location: "Herat" },
          headers: headers

      # Geo filter wins; the "Herat" text is ignored.
      expect(titles).to contain_exactly("Near")
    end
  end

  describe "combining filters" do
    before do
      create(:listing, :active, title: "Match",   price: 3_000, latitude: 34.5800, longitude: 69.2100)
      create(:listing, :active, title: "TooDear", price: 90_000, latitude: 34.5800, longitude: 69.2100)
    end

    it "applies price and distance together" do
      get "/api/v1/listings",
          params: { price_max: 10_000, latitude: kabul_lat, longitude: kabul_lng, radius: 10 },
          headers: headers

      expect(titles).to contain_exactly("Match")
    end
  end
end
