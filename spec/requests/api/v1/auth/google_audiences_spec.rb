require "rails_helper"

# The switch to a DEDICATED Hatiwal Google project (2026-10-29): the current web + iOS clients live in another
# product's project (1090253359225); new ones come from hatiwal-ece6b. During the switch the API must accept BOTH:
# the live web (old web id) keeps signing people in until the new web is deployed, and 1.2.0 apps sign in with the
# new ids. The new ids are a list (web, iOS; Android tokens carry the web id as their audience): ENV
# GOOGLE_CLIENT_IDS (comma-separated) or credentials google_client_ids. The old single ids (google_client_id,
# google_ios_client_id) keep counting until they are removed.
RSpec.describe "Google sign-in audiences during the project switch", type: :request do
  let(:old_web) { "1090253359225-oldweb.apps.googleusercontent.com" }
  let(:old_ios) { "1090253359225-oldios.apps.googleusercontent.com" }
  let(:new_web) { "691403843706-newweb.apps.googleusercontent.com" }
  let(:new_ios) { "691403843706-newios.apps.googleusercontent.com" }
  let(:env_ids) { nil }
  let(:cred_ids) { nil }

  before do
    allow(Rails.application.credentials).to receive(:[]).and_call_original
    allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(old_web)
    allow(Rails.application.credentials).to receive(:[]).with(:google_ios_client_id).and_return(old_ios)
    allow(Rails.application.credentials).to receive(:[]).with(:google_client_ids).and_return(cred_ids)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_IDS").and_return(env_ids)
  end

  def sign_in_with(aud, email: "switch-#{SecureRandom.hex(3)}@gmail.com")
    token = "tok-#{SecureRandom.hex(4)}"
    stub_request(:get, "https://oauth2.googleapis.com/tokeninfo").with(query: { id_token: token })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "sub" => SecureRandom.hex(6), "email" => email, "email_verified" => "true",
                         "given_name" => "A", "family_name" => "B", "aud" => aud }.to_json)
    post "/api/v1/auth/google", params: { id_token: token }, as: :json
    response
  end

  context "GOOGLE_CLIENT_IDS lists the new web + iOS clients" do
    let(:env_ids) { " #{new_web}, #{new_ios} ,," }

    it "accepts the NEW web client (and so the new Android tokens, whose audience is the web id)" do
      expect(sign_in_with(new_web)).to have_http_status(:ok)
    end

    it "accepts the NEW iOS client" do
      expect(sign_in_with(new_ios)).to have_http_status(:ok)
    end

    it "still accepts the OLD web and iOS clients (the live web, until the new one is deployed)" do
      expect(sign_in_with(old_web)).to have_http_status(:ok)
      expect(sign_in_with(old_ios)).to have_http_status(:ok)
    end

    it "still refuses any other audience" do
      res = sign_in_with("someone-elses-app.apps.googleusercontent.com")
      expect(res).to have_http_status(:unauthorized)
      expect(res.parsed_body["code"]).to eq("google_token_invalid")
    end
  end

  context "the list comes from credentials (google_client_ids) instead" do
    let(:cred_ids) { [ new_web, new_ios ] }

    it "accepts the new ids from credentials" do
      expect(sign_in_with(new_web)).to have_http_status(:ok)
      expect(sign_in_with(new_ios)).to have_http_status(:ok)
    end
  end
end
