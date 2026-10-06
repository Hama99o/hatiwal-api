require "swagger_helper"

# Email gate (owner, 2026-10-06, 1.1.6): opening a shop or applying for
# Verified (a person or a shop) needs a CONFIRMED email. Everything else keeps
# working unconfirmed (devise confirmable stays non-blocking). Google sign-ins
# are confirmed at creation. Existing shops and requests are untouched.
RSpec.describe "Email confirmation gate", type: :request do
  include ActiveJob::TestHelper

  let(:unconfirmed) { create(:user) }
  let(:category) { create(:category) }
  let(:shop_body) do
    { shop: { name: "Gate Shop", category_id: category.id, latitude: 34.3529, longitude: 62.204, address_line: "Shar-e-Naw" } }
  end

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user).merge("Content-Type" => "application/json")

  def expect_gate
    expect(response).to have_http_status(:forbidden)
    expect(json).to include("code" => "email_unconfirmed")
    expect(json["error"].presence || json["message"]).to be_present
  end

  path "/api/v1/shops" do
    post "open your shop — refused until the email is confirmed" do
      tags "Shops"
      description "403 { error, code: email_unconfirmed } when the caller's email is not confirmed " \
                  "(me.email_confirmed false). Resend the link with POST /api/v1/auth/confirmation {email}."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: { type: :object }
      let(:headers) { auth_headers_for(unconfirmed) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }
      let(:body) { shop_body }

      response "403", "email not confirmed" do
        run_test! do
          expect_gate
          expect(unconfirmed.owned_shops).to be_empty
        end
      end
    end
  end

  path "/api/v1/verification_requests" do
    post "apply for Verified — refused until the email is confirmed" do
      tags "Verification"
      description "403 { error, code: email_unconfirmed } for a person or a shop (subject shop:<id>) when the " \
                  "caller's email is not confirmed. Checked before the form, so no upload is wasted."
      consumes "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :verification_request, in: :formData, schema: { type: :object }
      let(:headers) { auth_headers_for(unconfirmed) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }
      let(:verification_request) { { document_type: "e_tazkira" } }

      response "403", "email not confirmed" do
        run_test! { expect_gate }
      end
    end
  end

  path "/api/v1/auth/confirmation" do
    post "send the confirmation link again" do
      tags "Auth"
      description "Resends the confirmation email. 5 per hour per IP (then 429)."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, properties: { email: { type: :string } }, required: %w[email] }
      let(:body) { { email: unconfirmed.email } }

      response "200", "sent" do
        run_test!
      end
    end
  end

  describe "opening a shop" do
    it "an unconfirmed user is refused; once confirmed, the same request opens it" do
      post "/api/v1/shops", params: shop_body.to_json, headers: h(unconfirmed)
      expect_gate

      unconfirmed.update!(confirmed_at: Time.current)
      post "/api/v1/shops", params: shop_body.to_json, headers: h(unconfirmed)
      expect(response).to have_http_status(:created)
    end

    it "speaks the person's language" do
      unconfirmed.update!(preferred_language: "fa")
      post "/api/v1/shops", params: shop_body.to_json, headers: h(unconfirmed)
      expect(json["error"].presence || json["message"]).to eq(I18n.t("accounts.email_unconfirmed", locale: :fa))
    end

    it "an existing shop of an unconfirmed owner keeps working (edit, products)" do
      shop = create(:shop, owner: unconfirmed)
      patch "/api/v1/shops/#{shop.id}", params: { shop: { description: "Still mine" } }.to_json, headers: h(unconfirmed)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "applying for Verified" do
    it "a person: refused unconfirmed, before any eligibility check" do
      post "/api/v1/verification_requests", params: { verification_request: { document_type: "e_tazkira" } },
                                            headers: auth_headers_for(unconfirmed)
      expect_gate
    end

    it "a shop: refused when its owner is unconfirmed" do
      shop = create(:shop, owner: unconfirmed)
      post "/api/v1/verification_requests", params: { subject: "shop:#{shop.id}", verification_request: { document_type: "e_tazkira" } },
                                            headers: auth_headers_for(unconfirmed)
      expect_gate
    end

    it "a waiting request of a now-unconfirmed user is untouched and can still be read and cancelled" do
      eligible = create(:user, :verification_eligible)
      request = create(:verification_request, user: eligible)
      eligible.update_columns(confirmed_at: nil) # e.g. an email change waiting for its link
      unconfirmed = eligible
      get "/api/v1/verification_requests/current", headers: auth_headers_for(unconfirmed)
      expect(response).to have_http_status(:ok)
      delete "/api/v1/verification_requests/#{request.id}", headers: auth_headers_for(unconfirmed)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "me.email_confirmed" do
    it "is false until confirmed, then true" do
      get "/api/v1/users/me", headers: auth_headers_for(unconfirmed)
      expect(json["user"]).to include("email_confirmed" => false)
      unconfirmed.update!(confirmed_at: Time.current)
      get "/api/v1/users/me", headers: auth_headers_for(unconfirmed)
      expect(json["user"]).to include("email_confirmed" => true)
    end
  end

  describe "a Google sign-in" do
    let(:google_client_id) { "test-client-id.apps.googleusercontent.com" }

    before do
      allow(Rails.application.credentials).to receive(:[]).and_call_original
      allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(google_client_id)
      allow(Rails.application.credentials).to receive(:[]).with(:google_ios_client_id).and_return("ios-#{google_client_id}")
      payload = { "sub" => "998877", "email" => "gate.google@gmail.com", "email_verified" => "true",
                  "given_name" => "Gul", "family_name" => "Ahmadi", "aud" => google_client_id }
      stub_request(:get, "https://oauth2.googleapis.com/tokeninfo").with(query: { id_token: "gate-token" })
                                                                   .to_return(status: 200, body: payload.to_json,
                                                                              headers: { "Content-Type" => "application/json" })
    end

    it "counts as confirmed and may open a shop at once" do
      post "/api/v1/auth/google", params: { id_token: "gate-token" }
      expect(response).to have_http_status(:ok)
      user = User.find_by!(email: "gate.google@gmail.com")
      expect(user.email_confirmed?).to be(true)

      tokens = json.slice("access-token", "client", "uid") # the body carries the tokens
      post "/api/v1/shops", params: shop_body.to_json, headers: tokens.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
    end
  end

  describe "resend (POST /api/v1/auth/confirmation)" do
    it "sends the link again, and is limited to 5 an hour" do
      perform_enqueued_jobs do
        expect do
          post "/api/v1/auth/confirmation", params: { email: unconfirmed.email }
        end.to change { ActionMailer::Base.deliveries.count }.by(1)
      end
      expect(response).to have_http_status(:ok)

      4.times { post "/api/v1/auth/confirmation", params: { email: unconfirmed.email } }
      expect(response).to have_http_status(:ok)
      post "/api/v1/auth/confirmation", params: { email: unconfirmed.email }
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
