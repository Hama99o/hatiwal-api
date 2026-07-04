require "rails_helper"

RSpec.describe "Api::V1::Listings hide/unhide", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:listing) { create(:listing, :active) }

  describe "POST /api/v1/listings/:id/hide" do
    it "requires authentication" do
      post "/api/v1/listings/#{listing.id}/hide", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "hides the listing for the current user" do
      expect do
        post "/api/v1/listings/#{listing.id}/hide", headers: headers, as: :json
      end.to change(user.hidden_listings, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["hidden"]).to be true
      expect(body["id"]).to be_present
    end

    it "is idempotent — hiding twice does not duplicate" do
      post "/api/v1/listings/#{listing.id}/hide", headers: headers, as: :json
      expect do
        post "/api/v1/listings/#{listing.id}/hide", headers: headers, as: :json
      end.not_to change(user.hidden_listings, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/listings/:id/unhide" do
    it "requires authentication" do
      delete "/api/v1/listings/#{listing.id}/unhide", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "removes a hidden listing" do
      create(:hidden_listing, user: user, listing: listing)
      expect do
        delete "/api/v1/listings/#{listing.id}/unhide", headers: headers, as: :json
      end.to change(user.hidden_listings, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["hidden"]).to be false
    end

    it "is a no-op when the listing was not hidden" do
      expect do
        delete "/api/v1/listings/#{listing.id}/unhide", headers: headers, as: :json
      end.not_to change(HiddenListing, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/listings — feed exclusion" do
    it "excludes a listing the current user hid, but only for that user" do
      hidden_listing = create(:listing, :active)
      visible_listing = create(:listing, :active)
      other_user = create(:user)

      create(:hidden_listing, user: user, listing: hidden_listing)

      get "/api/v1/listings", headers: headers, as: :json
      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to include(visible_listing.id)
      expect(ids).not_to include(hidden_listing.id)

      # A different signed-in user still sees it.
      get "/api/v1/listings", headers: auth_headers_for(other_user), as: :json
      other_ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(other_ids).to include(hidden_listing.id)

      # A guest (no auth headers) still sees it too.
      get "/api/v1/listings", as: :json
      guest_ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(guest_ids).to include(hidden_listing.id)
    end

    it "restores the listing to the feed after unhide" do
      create(:hidden_listing, user: user, listing: listing)

      get "/api/v1/listings", headers: headers, as: :json
      expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).not_to include(listing.id)

      delete "/api/v1/listings/#{listing.id}/unhide", headers: headers, as: :json

      get "/api/v1/listings", headers: headers, as: :json
      expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).to include(listing.id)
    end
  end
end
