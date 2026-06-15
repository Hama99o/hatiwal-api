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

    context "listings_count excludes expired active listings" do
      it "counts only active non-expired listings, matching what GET /listings?user_id= returns" do
        # One active listing that is still live (no expiry set).
        create(:listing, :active, user: seller)
        # One active listing whose expiry has already passed — must NOT be counted.
        create(:listing, :expired, user: seller)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["listings_count"]).to eq(1),
          "Expected listings_count to be 1 (only the non-expired active listing), " \
          "but got #{body['listings_count']}. The header count must match the buyer feed grid."

        # Confirm the profile count matches the browsable scope directly, which
        # is what the buyer grid (GET /listings?user_id=) uses under the hood.
        browsable_count = seller.listings.active.not_expired.count
        expect(browsable_count).to eq(body["listings_count"]),
          "listings_count in the profile header (#{body['listings_count']}) " \
          "must equal seller.listings.active.not_expired.count (#{browsable_count})"
      end

      it "does not affect sold_count — sold listings are not expiry-gated" do
        create(:listing, :sold, user: seller)
        create(:listing, :expired, user: seller)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        body = JSON.parse(response.body)["user"]
        expect(body["sold_count"]).to eq(1)
        # The expired active listing does not inflate listings_count.
        expect(body["listings_count"]).to eq(0)
      end
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
