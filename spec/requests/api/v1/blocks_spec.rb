require "rails_helper"

RSpec.describe "Api::V1::Blocks", type: :request do
  let(:user)         { create(:user) }
  let(:other_user)   { create(:user) }
  let(:headers)      { auth_headers_for(user) }

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
