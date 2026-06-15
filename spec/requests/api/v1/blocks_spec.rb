require "rails_helper"

RSpec.describe "Api::V1::Blocks", type: :request do
  let(:user)         { create(:user) }
  let(:other_user)   { create(:user) }
  let(:headers)      { auth_headers_for(user) }

  describe "GET /api/v1/blocks" do
    it "requires authentication" do
      get "/api/v1/blocks", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns only the current user's blocked users under the users key" do
      blocked_a = create(:user)
      blocked_b = create(:user)
      create(:block, blocker: user, blocked: blocked_a)
      create(:block, blocker: user, blocked: blocked_b)
      # A block created by someone else must not leak into this user's list.
      create(:block, blocker: other_user, blocked: create(:user))

      get "/api/v1/blocks", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("users")
      ids = body["users"].map { |u| u["id"] }
      expect(ids).to contain_exactly(blocked_a.id, blocked_b.id)
      # :public view exposes name + verified, never PII (no email/phone).
      first = body["users"].first
      expect(first).to include("full_name", "verified")
      expect(first).not_to include("email", "phone")
    end

    it "returns an empty users array when nothing is blocked" do
      get "/api/v1/blocks", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body["users"]).to eq([])
    end

    it "orders blocked users newest-first" do
      older = create(:user)
      newer = create(:user)
      create(:block, blocker: user, blocked: older, created_at: 2.days.ago)
      create(:block, blocker: user, blocked: newer, created_at: 1.hour.ago)

      get "/api/v1/blocks", headers: headers, as: :json
      ids = JSON.parse(response.body)["users"].map { |u| u["id"] }
      expect(ids).to eq([ newer.id, older.id ])
    end
  end

  describe "POST /api/v1/blocks/:user_id" do
    it "requires authentication" do
      post "/api/v1/users/#{other_user.id}/block", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "blocks another user and returns 204" do
      post "/api/v1/users/#{other_user.id}/block", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
      expect(user.reload.blocked?(other_user)).to be true
    end

    it "is idempotent — blocking twice does not raise an error" do
      create(:block, blocker: user, blocked: other_user)
      expect do
        post "/api/v1/users/#{other_user.id}/block", headers: headers, as: :json
      end.not_to change(Block, :count)
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for a non-existent user" do
      post "/api/v1/users/0/block", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/blocks/:user_id" do
    it "requires authentication" do
      delete "/api/v1/users/#{other_user.id}/block", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "unblocks a previously blocked user and returns 204" do
      create(:block, blocker: user, blocked: other_user)
      delete "/api/v1/users/#{other_user.id}/block", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
      expect(user.reload.blocked?(other_user)).to be false
    end

    it "returns 204 even when no block existed (idempotent)" do
      delete "/api/v1/users/#{other_user.id}/block", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for a non-existent user" do
      delete "/api/v1/users/0/block", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
