require "rails_helper"

# The signed-in user's view of their own warnings (for the mobile banner).
RSpec.describe "Warnings API", type: :request do
  let(:user)    { create(:user) }
  let(:admin)   { create(:admin_user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/users/warnings" do
    it "returns the user's warnings with active count + threshold" do
      user.issue_warning!(admin_user: admin, reason: "Spam listings", category: :spam)

      get "/api/v1/users/warnings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["warnings"].length).to eq(1)
      expect(body["warnings"].first).to include("reason" => "Spam listings", "active" => true)
      expect(body["meta"]).to include("active_count" => 1, "threshold" => 3)
    end

    it "requires authentication" do
      get "/api/v1/users/warnings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/users/warnings/mark_seen" do
    it "acknowledges the user's active warnings" do
      warning = user.issue_warning!(admin_user: admin, reason: "x")

      put "/api/v1/users/warnings/mark_seen", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(warning.reload.acknowledged_at).to be_present
    end
  end

  describe "GET /api/v1/users/me" do
    it "includes the active warning count and threshold" do
      user.issue_warning!(admin_user: admin, reason: "x")

      get "/api/v1/users/me", headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["user"]["active_warnings_count"]).to eq(1)
      expect(body["user"]["warning_threshold"]).to eq(3)
    end
  end
end
