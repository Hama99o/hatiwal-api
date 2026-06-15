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
      expect(body["verified"]).to be(false)
      # PII must not appear in the public view
      expect(body).not_to have_key("email")
      expect(body).not_to have_key("phone")
      expect(body).not_to have_key("latitude")
      expect(body).not_to have_key("longitude")
      expect(body).not_to have_key("preferred_language")
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

    context "blocked field" do
      it "returns blocked: false when the viewer has not blocked the seller" do
        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).to have_key("blocked")
        expect(body["blocked"]).to be(false)
      end

      it "returns blocked: true when the viewer has previously blocked the seller" do
        create(:block, blocker: requester, blocked: seller)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).to have_key("blocked")
        expect(body["blocked"]).to be(true)
      end

      it "returns blocked: false for a different viewer who has not blocked the seller" do
        # Blocker blocks the seller, but a third user gets false
        blocker = create(:user)
        create(:block, blocker: blocker, blocked: seller)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["blocked"]).to be(false)
      end
    end
  end
end
