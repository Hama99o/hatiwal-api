require "rails_helper"

RSpec.describe "Api::V1::Users::PublicProfiles", type: :request do
  let(:requester) { create(:user) }
  let(:seller)    { create(:user, firstname: "Ahmad", lastname: "Shah") }
  let(:headers)   { auth_headers_for(requester) }

  describe "GET /api/v1/users/:id/public_profile" do
    it "requires authentication" do
      get "/api/v1/users/#{seller.id}/public_profile", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the seller's public profile with trust fields" do
      create(:listing, :active, user: seller)
      create(:listing, :sold, user: seller)
      create(:listing, :sold, user: seller)

      get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["full_name"]).to eq("Ahmad Shah")
      expect(body["listings_count"]).to eq(1)
      expect(body["sold_count"]).to eq(2)
      expect(body["member_since"]).to be_present
      expect(body).not_to have_key("phone")
      expect(body["verified"]).to be(false)
    end

    it "reports a verified seller" do
      verified_seller = create(:user, :verified)
      get "/api/v1/users/#{verified_seller.id}/public_profile", headers: headers, as: :json
      expect(JSON.parse(response.body)["user"]["verified"]).to be(true)
    end

    it "returns 404 for a non-existent user" do
      get "/api/v1/users/0/public_profile", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
