require "rails_helper"

# "Seen" state: a listing the buyer has already opened is flagged so the card
# can show a viewed treatment when browsing/searching again.
RSpec.describe "Api::V1::Listings seen state", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/listings/:id" do
    it "records a view for the current user" do
      listing = create(:listing, :active)

      expect do
        get "/api/v1/listings/#{listing.id}", headers: headers
      end.to change(ListingView, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["listing"]["is_viewed"]).to be true
    end

    it "does not create duplicate views on repeat opens" do
      listing = create(:listing, :active)

      get "/api/v1/listings/#{listing.id}", headers: headers
      expect do
        get "/api/v1/listings/#{listing.id}", headers: headers
      end.not_to change(ListingView, :count)
    end
  end

  describe "GET /api/v1/listings" do
    it "flags already-viewed listings as is_viewed" do
      seen = create(:listing, :active, title: "Seen")
      create(:listing, :active, title: "Unseen")
      create(:listing_view, user: user, listing: seen)

      get "/api/v1/listings", headers: headers

      body = JSON.parse(response.body)
      flags = body["listings"].to_h { |l| [ l["title"], l["is_viewed"] ] }
      expect(flags["Seen"]).to be true
      expect(flags["Unseen"]).to be false
    end
  end
end
