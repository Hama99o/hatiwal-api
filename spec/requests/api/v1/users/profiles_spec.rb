require "rails_helper"

RSpec.describe "Api::V1::Users::Profiles", type: :request do
  let(:user)    { create(:user, firstname: "Ahmad", lastname: "Shah", preferred_language: "ps") }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/users/me" do
    it "requires authentication" do
      get "/api/v1/users/me", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user's private profile" do
      get "/api/v1/users/me", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["id"]).to eq(user.id)
      expect(body["full_name"]).to eq("Ahmad Shah")
      expect(body).to have_key("phone")
      expect(body).to have_key("avatar_url")
      expect(body).to have_key("seller_mode")
      expect(body).to have_key("preferred_theme")
      # The :me view must include the owner's own email
      expect(body["email"]).to eq(user.email)
    end

    it "includes dashboard counts (no money total)" do
      create(:listing, :active, user: user)
      create(:listing, :active, user: user)
      create(:listing, :sold, user: user)

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body["items_active_count"]).to eq(2)
      expect(body["items_sold_count"]).to eq(1)
      expect(body).to have_key("saved_items_count")
      expect(body).to have_key("unread_message_count")
      expect(body).not_to have_key("total_sales") # money never summed across currencies
    end
  end

  describe "PUT /api/v1/users/me" do
    it "updates editable profile fields" do
      put "/api/v1/users/me",
          params: { user: { firstname: "Mohammad", city: "Herat", preferred_language: "fa" } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.firstname).to eq("Mohammad")
      expect(user.city).to eq("Herat")
      expect(user.preferred_language).to eq("fa")
    end

    it "toggles seller_mode on and off" do
      put "/api/v1/users/me",
          params: { user: { seller_mode: true } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["seller_mode"]).to eq(true)
      expect(user.reload.seller_mode).to eq(true)

      put "/api/v1/users/me",
          params: { user: { seller_mode: false } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.seller_mode).to eq(false)
    end

    it "accepts an avatar file upload and returns avatar_url" do
      avatar = fixture_file_upload(
        Rails.root.join("spec/fixtures/files/test_image.jpg"),
        "image/jpeg"
      )

      put "/api/v1/users/me",
          params: { user: { avatar: avatar } },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["avatar_url"]).to be_present
      expect(user.reload.avatar).to be_attached
    end

    it "422s on an invalid preferred_language" do
      put "/api/v1/users/me",
          params: { user: { preferred_language: "ru" } },
          headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end

    it "updates preferred_theme" do
      put "/api/v1/users/me",
          params: { user: { preferred_theme: "dark" } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["preferred_theme"]).to eq("dark")
      expect(user.reload.preferred_theme).to eq("dark")
    end

    it "422s on an invalid preferred_theme" do
      put "/api/v1/users/me",
          params: { user: { preferred_theme: "blue" } },
          headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end

    context "push_token" do
      let(:valid_token) { "ExponentPushToken[xxxxxxxxxxxxxxxxxxxxxx]" }

      it "saves a push_token on first registration" do
        put "/api/v1/users/me",
            params: { user: { push_token: valid_token } },
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.push_token).to eq(valid_token)
      end

      it "updates an existing push_token" do
        user.update!(push_token: "ExponentPushToken[old_token_value_here]")

        new_token = "ExponentPushToken[new_token_value_here_xx]"
        put "/api/v1/users/me",
            params: { user: { push_token: new_token } },
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.push_token).to eq(new_token)
      end

      it "422s when push_token exceeds 200 characters" do
        long_token = "a" * 201
        put "/api/v1/users/me",
            params: { user: { push_token: long_token } },
            headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["errors"]).to be_present
      end

      it "allows clearing push_token with an empty string" do
        user.update!(push_token: valid_token)

        put "/api/v1/users/me",
            params: { user: { push_token: "" } },
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.push_token).to be_blank
      end
    end
  end

  describe "away_until — PUT /api/v1/users/me" do
    it "sets away_until to a future datetime" do
      future = 5.days.from_now.iso8601

      put "/api/v1/users/me",
          params: { user: { away_until: future } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body).to have_key("away_until")
      # The date should be present and non-nil
      expect(body["away_until"]).to be_present
      expect(user.reload.away_until).to be_present
      expect(user.away?).to be true
    end

    it "clears away_until by sending null" do
      user.update!(away_until: 5.days.from_now)

      put "/api/v1/users/me",
          params: { user: { away_until: nil } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.away_until).to be_nil
      expect(user.away?).to be false
    end

    it "returns away_until in the :me response when set" do
      future = 3.days.from_now
      user.update!(away_until: future)

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body).to have_key("away_until")
      expect(body["away_until"]).to be_present
    end

    it "returns away_until as nil in :me response when not set" do
      user.update!(away_until: nil)

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body).to have_key("away_until")
      expect(body["away_until"]).to be_nil
    end

    it "exposes away_until in public profile only when currently away" do
      other = create(:user, away_until: 7.days.from_now)

      get "/api/v1/users/#{other.id}", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body["away_until"]).to be_present
    end

    it "returns away_until as nil in public profile when past or nil" do
      other = create(:user)
      other.update_column(:away_until, 2.days.ago)

      get "/api/v1/users/#{other.id}", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body["away_until"]).to be_nil
    end

    it "returns is_away: true in public profile when currently away" do
      other = create(:user, away_until: 7.days.from_now)

      get "/api/v1/users/#{other.id}", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body["is_away"]).to be(true)
    end

    it "returns is_away: false in public profile when not away" do
      other = create(:user, away_until: nil)

      get "/api/v1/users/#{other.id}", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body["is_away"]).to be(false)
    end

    it "returns is_away: false in :me response when not away" do
      user.update_column(:away_until, nil)

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body).to have_key("is_away")
      expect(body["is_away"]).to be(false)
    end

    it "returns is_away: true in :me response when currently away" do
      user.update_column(:away_until, 3.days.from_now)

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)["user"]
      expect(body["is_away"]).to be(true)
    end

    it "422s when away_until is set to a past datetime" do
      put "/api/v1/users/me",
          params: { user: { away_until: 1.day.ago.iso8601 } },
          headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end
  end

  describe "GET /api/v1/users/:id" do
    it "returns another user's public profile with trust fields" do
      other = create(:user, firstname: "Fatima", lastname: "Noori")
      create(:listing, :active, user: other)
      create(:listing, :sold, user: other)

      get "/api/v1/users/#{other.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["full_name"]).to eq("Fatima Noori")
      expect(body["listings_count"]).to eq(1)
      expect(body["sold_count"]).to eq(1)
      expect(body["member_since"]).to be_present
      expect(body).to have_key("avatar_url")
      # PII must not appear in the :public view
      expect(body).not_to have_key("email")
      expect(body).not_to have_key("phone")
      expect(body).not_to have_key("latitude")
      expect(body).not_to have_key("longitude")
      expect(body).not_to have_key("preferred_language")
    end

    context "blocked field" do
      let(:other) { create(:user) }

      it "returns blocked: false when the viewer has not blocked the other user" do
        get "/api/v1/users/#{other.id}", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).to have_key("blocked")
        expect(body["blocked"]).to be(false)
      end

      it "returns blocked: true when the viewer has previously blocked the other user" do
        create(:block, blocker: user, blocked: other)

        get "/api/v1/users/#{other.id}", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).to have_key("blocked")
        expect(body["blocked"]).to be(true)
      end

      it "does not include blocked in the :me view" do
        get "/api/v1/users/me", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)["user"]
        expect(body).not_to have_key("blocked")
      end
    end
  end
end
