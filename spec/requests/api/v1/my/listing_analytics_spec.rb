require "rails_helper"

RSpec.describe "Api::V1::My::ListingAnalytics", type: :request do
  let(:user)    { create(:user) }
  let(:other)   { create(:user) }
  let(:listing) { create(:listing, user: user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/my/listings/:listing_id/analytics" do
    it "requires authentication" do
      get "/api/v1/my/listings/#{listing.id}/analytics", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 when listing belongs to another user" do
      other_listing = create(:listing, user: other)
      get "/api/v1/my/listings/#{other_listing.id}/analytics", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 7 entries with date and count keys" do
      get "/api/v1/my/listings/#{listing.id}/analytics", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to have_key("analytics")
      entries = data["analytics"]
      expect(entries.length).to eq(7)
      entries.each do |entry|
        expect(entry).to have_key("date")
        expect(entry).to have_key("count")
      end
    end

    it "fills in 0 for days with no views" do
      get "/api/v1/my/listings/#{listing.id}/analytics", headers: headers, as: :json

      entries = JSON.parse(response.body)["analytics"]
      expect(entries.map { |e| e["count"] }).to all(eq(0))
    end

    it "counts distinct viewers whose last_viewed_at falls on a given day" do
      viewer1 = create(:user)
      viewer2 = create(:user)

      today = Time.current

      create(:listing_view, listing: listing, user: viewer1, last_viewed_at: today)
      create(:listing_view, listing: listing, user: viewer2, last_viewed_at: today)

      get "/api/v1/my/listings/#{listing.id}/analytics", headers: headers, as: :json

      entries = JSON.parse(response.body)["analytics"]
      today_entry = entries.last
      expect(today_entry["date"]).to eq(Date.current.to_s)
      expect(today_entry["count"]).to eq(2)
    end

    it "does not count views outside the 7-day window" do
      viewer = create(:user)
      create(:listing_view, listing: listing, user: viewer,
             last_viewed_at: 8.days.ago)

      get "/api/v1/my/listings/#{listing.id}/analytics", headers: headers, as: :json

      entries = JSON.parse(response.body)["analytics"]
      expect(entries.map { |e| e["count"] }.sum).to eq(0)
    end

    it "does not include views from another listing" do
      other_listing = create(:listing, user: user)
      viewer = create(:user)
      create(:listing_view, listing: other_listing, user: viewer,
             last_viewed_at: Time.current)

      get "/api/v1/my/listings/#{listing.id}/analytics", headers: headers, as: :json

      entries = JSON.parse(response.body)["analytics"]
      expect(entries.map { |e| e["count"] }.sum).to eq(0)
    end

    it "dates are ordered oldest to newest" do
      get "/api/v1/my/listings/#{listing.id}/analytics", headers: headers, as: :json

      entries = JSON.parse(response.body)["analytics"]
      dates = entries.map { |e| Date.parse(e["date"]) }
      expect(dates).to eq(dates.sort)
    end
  end
end
