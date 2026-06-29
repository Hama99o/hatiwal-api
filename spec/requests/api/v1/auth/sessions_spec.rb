require "rails_helper"

RSpec.describe "Api::V1::Auth::SessionsController", type: :request do
  let(:password) { "password123" }
  let!(:user) { create(:user, password: password, push_token: "ExponentPushToken[abc123]") }

  def login
    post "/api/v1/auth/sign_in", params: { email: user.email, password: password }, as: :json
    response.headers.slice("access-token", "client", "uid", "token-type")
  end

  describe "DELETE /api/v1/auth/sign_out" do
    context "when logged in with a push token registered" do
      it "clears the push_token on logout" do
        headers = login
        expect(user.reload.push_token).to eq("ExponentPushToken[abc123]")

        delete "/api/v1/auth/sign_out", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.push_token).to be_nil
      end

      it "prevents the logged-out device receiving notifications meant for others" do
        headers = login
        delete "/api/v1/auth/sign_out", headers: headers, as: :json

        # After logout the token is gone — SendMessagePushJob will skip this user
        expect(user.reload.push_token).to be_nil
      end
    end

    context "when the user has no push token" do
      let!(:user) { create(:user, password: password, push_token: nil) }

      it "logs out cleanly without error" do
        headers = login
        delete "/api/v1/auth/sign_out", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
