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
