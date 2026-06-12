require "rails_helper"

RSpec.describe "Api::V1::Listings save/unsave", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:listing) { create(:listing, :active) }

  describe "POST /api/v1/listings/:id/save" do
    it "requires authentication" do
      post "/api/v1/listings/#{listing.id}/save", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "saves the listing for the current user" do
      expect do
        post "/api/v1/listings/#{listing.id}/save", headers: headers, as: :json
      end.to change(user.saved_listings, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["saved"]).to be true
      expect(body["id"]).to be_present
    end

    it "is idempotent — saving twice does not duplicate" do
      post "/api/v1/listings/#{listing.id}/save", headers: headers, as: :json
      expect do
        post "/api/v1/listings/#{listing.id}/save", headers: headers, as: :json
      end.not_to change(user.saved_listings, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/listings/:id/unsave" do
    it "removes a saved listing" do
      create(:saved_listing, user: user, listing: listing)
      expect do
        delete "/api/v1/listings/#{listing.id}/unsave", headers: headers, as: :json
      end.to change(user.saved_listings, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["saved"]).to be false
    end

    it "is a no-op when the listing was not saved" do
      expect do
        delete "/api/v1/listings/#{listing.id}/unsave", headers: headers, as: :json
      end.not_to change(SavedListing, :count)
      expect(response).to have_http_status(:ok)
    end
  end
end
