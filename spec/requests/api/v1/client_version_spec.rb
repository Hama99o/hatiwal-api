require "rails_helper"

RSpec.describe "Client version reporting", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  it "records X-App-Version / X-App-Platform from any authenticated request" do
    get "/api/v1/conversations", headers: headers.merge("X-App-Version" => "1.1.0", "X-App-Platform" => "ios")

    expect(response).to have_http_status(:ok)
    expect(user.reload).to have_attributes(last_app_version: "1.1.0", last_app_platform: "ios")
  end

  it "marks a headerless request from the native app as a legacy client" do
    get "/api/v1/conversations", headers: headers.merge("User-Agent" => "okhttp/4.12.0")

    expect(user.reload.legacy_client_seen_at).to be_present
  end

  it "never fails the request when recording goes wrong" do
    allow_any_instance_of(User).to receive(:record_client!).and_raise(ActiveRecord::StatementInvalid, "boom")

    get "/api/v1/conversations", headers: headers.merge("X-App-Version" => "1.1.0")

    expect(response).to have_http_status(:ok)
  end

  it "records nothing for an anonymous request" do
    get "/api/v1/listings", headers: { "X-App-Version" => "1.1.0", "User-Agent" => "okhttp/4.12.0" }

    expect(response).to have_http_status(:ok)
  end

  describe "PUT /me push_registration_error" do
    it "stores why the app couldn't register for push" do
      put "/api/v1/users/me", headers: headers,
                              params: { user: { push_registration_error: "token: Default FirebaseApp is not initialized" } }

      expect(response).to have_http_status(:ok)
      expect(user.reload.push_registration_error).to eq("token: Default FirebaseApp is not initialized")
    end

    it "caps a huge or hostile value instead of rejecting the request" do
      put "/api/v1/users/me", headers: headers,
                              params: { user: { push_registration_error: "<script>alert(1)</script>#{'A' * 5000}" } }

      expect(response).to have_http_status(:ok)
      expect(user.reload.push_registration_error.length).to eq(ClientVersionReporting::PUSH_ERROR_MAX)
    end
  end
end
