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

    context "response_rate_percent and response_time_label fields" do
      it "returns both fields as nil when seller has fewer than 5 conversations" do
        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).to have_key("response_rate_percent")
        expect(body).to have_key("response_time_label")
        expect(body["response_rate_percent"]).to be_nil
        expect(body["response_time_label"]).to be_nil
      end

      it "returns non-nil fields when seller has >=5 conversations with quick replies" do
        listing = create(:listing, :active, user: seller)
        5.times do
          buyer = create(:user)
          conv = create(:conversation, listing: listing, buyer: buyer, seller: seller)
          first_msg = create(:message, conversation: conv, user: buyer,
                                       created_at: conv.created_at + 1.minute)
          create(:message, conversation: conv, user: seller,
                           created_at: first_msg.created_at + 30.minutes)
        end

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["response_rate_percent"]).to eq(100)
        expect(body["response_time_label"]).to eq("within_one_hour")
      end

      it "returns response_rate_percent=0 and response_time_label=nil when seller never replied" do
        listing = create(:listing, :active, user: seller)
        5.times do
          buyer = create(:user)
          conv  = create(:conversation, listing: listing, buyer: buyer, seller: seller)
          create(:message, conversation: conv, user: buyer,
                           created_at: conv.created_at + 1.minute)
          # no seller reply
        end

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["response_rate_percent"]).to eq(0)
        # time_label must be nil so mobile can suppress the contradictory badge
        expect(body["response_time_label"]).to be_nil
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

    context "last_active_label recency signal" do
      it 'returns "today" for a seller who signed in 1 hour ago' do
        seller.update!(last_sign_in_at: 1.hour.ago)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).to have_key("last_active_label")
        expect(body["last_active_label"]).to eq("today")
      end

      it 'returns "this_week" for a seller who signed in 3 days ago' do
        seller.update!(last_sign_in_at: 3.days.ago)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["last_active_label"]).to eq("this_week")
      end

      it 'returns "this_month" for a seller who signed in 20 days ago' do
        seller.update!(last_sign_in_at: 20.days.ago)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["last_active_label"]).to eq("this_month")
      end

      it "returns nil for a seller who signed in 60 days ago" do
        seller.update!(last_sign_in_at: 60.days.ago)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["last_active_label"]).to be_nil
      end

      it "returns nil when last_sign_in_at is nil" do
        seller.update!(last_sign_in_at: nil)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body["last_active_label"]).to be_nil
      end

      it "does NOT expose the raw last_sign_in_at timestamp in the public profile" do
        seller.update!(last_sign_in_at: 1.hour.ago)

        get "/api/v1/users/#{seller.id}/public_profile", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).not_to have_key("last_sign_in_at")
      end
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
