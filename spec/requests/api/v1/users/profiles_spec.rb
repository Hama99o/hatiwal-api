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

    it "422s on an invalid preferred_language" do
      put "/api/v1/users/me",
          params: { user: { preferred_language: "ru" } },
          headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end
  end

  describe "GET /api/v1/users/:id" do
    it "returns another user's public profile" do
      other = create(:user, firstname: "Fatima", lastname: "Noori")
      create(:listing, :active, user: other)

      get "/api/v1/users/#{other.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["user"]
      expect(body["full_name"]).to eq("Fatima Noori")
      expect(body["listings_count"]).to eq(1)
      expect(body).not_to have_key("phone")
    end
  end
end
