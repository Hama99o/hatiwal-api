require "rails_helper"

# A suspended/banned ("blocked") user must be kept out of the app and told why.
RSpec.describe "Account blocking", type: :request do
  describe "logging in while blocked" do
    it "rejects a banned user, with the reason folded into the message" do
      user = create(:user, status: :banned, block_reason: "Repeatedly posting spam")

      post "/api/v1/auth/sign_in", params: { email: user.email, password: user.password }, as: :json

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      # Message states the block AND includes the reason.
      expect(body["errors"].join).to match(/banned/i)
      expect(body["errors"].join).to include("Repeatedly posting spam")
      expect(body["status"]).to eq("banned")
      expect(body["reason"]).to eq("Repeatedly posting spam")
    end

    it "falls back to the default message when no reason was given" do
      user = create(:user, status: :banned, block_reason: nil)

      post "/api/v1/auth/sign_in", params: { email: user.email, password: user.password }, as: :json

      body = JSON.parse(response.body)
      expect(body["errors"].join).to match(/banned/i)
      expect(body["errors"].join).not_to include("Reason:")
      expect(body["reason"]).to be_nil
    end

    it "rejects a suspended user" do
      user = create(:user, status: :suspended)
      post "/api/v1/auth/sign_in", params: { email: user.email, password: user.password }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["status"]).to eq("suspended")
    end

    it "lets an active user log in" do
      user = create(:user, status: :active)
      post "/api/v1/auth/sign_in", params: { email: user.email, password: user.password }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "blocked while holding a valid token" do
    it "rejects authenticated requests with a clear 403 + reason" do
      user = create(:user, status: :active)
      headers = auth_headers_for(user)

      user.update!(status: :banned, block_reason: "Fraudulent listings")

      get "/api/v1/my/listings", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("account_banned")
      expect(body["reason"]).to eq("Fraudulent listings")
      expect(body["message"]).to include("Fraudulent listings")
    end

    it "still lets active users through" do
      user = create(:user, status: :active)
      headers = auth_headers_for(user)
      get "/api/v1/my/listings", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
