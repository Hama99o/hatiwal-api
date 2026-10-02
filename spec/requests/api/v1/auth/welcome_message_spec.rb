require "rails_helper"

# Both doors into account creation queue the Support welcome
# (WelcomeSupportMessageJob); signing in to an existing account does not.
RSpec.describe "Welcome message on sign-up", type: :request do
  include ActiveJob::TestHelper

  describe "email sign-up (POST /api/v1/auth)" do
    def sign_up(email:)
      post "/api/v1/auth",
           params: { email: email, password: "Password123!", password_confirmation: "Password123!",
                     firstname: "New", lastname: "Comer", preferred_language: "ps" },
           as: :json
    end

    it "queues the welcome for the new account" do
      expect { sign_up(email: "newcomer@example.com") }
        .to have_enqueued_job(WelcomeSupportMessageJob).with(kind_of(Integer))

      expect(WelcomeSupportMessageJob).to have_been_enqueued.with(User.find_by!(email: "newcomer@example.com").id)
    end

    it "queues nothing when the sign-up fails" do
      create(:user, email: "taken@example.com")

      expect { sign_up(email: "taken@example.com") }.not_to have_enqueued_job(WelcomeSupportMessageJob)
    end
  end

  describe "Google sign-in (POST /api/v1/auth/google)" do
    let(:email) { "ahmad.google@example.com" }

    before do
      allow(Rails.application.credentials).to receive(:[]).and_call_original
      allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return("test-client-id")
      allow(Rails.application.credentials).to receive(:[]).with(:google_ios_client_id).and_return("test-ios-client-id")
      stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
        .with(query: { id_token: "tok" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { sub: "g-123", email: email, email_verified: "true", given_name: "Ahmad",
                           family_name: "Karimi", aud: "test-client-id" }.to_json)
    end

    it "queues the welcome when the Google account is new" do
      post "/api/v1/auth/google", params: { id_token: "tok" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(WelcomeSupportMessageJob).to have_been_enqueued.with(User.find_by!(email: email).id)
    end

    it "queues nothing for a returning user" do
      create(:user, email: email)

      expect { post "/api/v1/auth/google", params: { id_token: "tok" }, as: :json }
        .not_to have_enqueued_job(WelcomeSupportMessageJob)
    end
  end
end
