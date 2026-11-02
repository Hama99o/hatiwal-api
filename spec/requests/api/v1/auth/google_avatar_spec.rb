require "rails_helper"

# POST /api/v1/auth/google: a NEW account queues GoogleAvatarImportJob with the
# token's `picture`; the sign-in answers without waiting for it. A returning or
# linked account is never touched, even one without an avatar (owner, 2026-10-29).
RSpec.describe "Google sign-in avatar", type: :request do
  include ActiveJob::TestHelper

  let(:client_id) { "test-client-id.apps.googleusercontent.com" }
  let(:email) { "photo.person@gmail.com" }
  let(:picture) { "https://lh3.googleusercontent.com/a/ACg8ocK-photo=s96-c" }

  before do
    allow(Rails.application.credentials).to receive(:[]).and_call_original
    allow(Rails.application.credentials).to receive(:[]).with(:google_client_id).and_return(client_id)
    stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
      .with(query: { id_token: "tok" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { sub: "7", email: email, email_verified: "true", given_name: "Photo", family_name: "Person",
                         picture: picture, aud: client_id }.to_json)
  end

  def sign_in = post("/api/v1/auth/google", params: { id_token: "tok" }, as: :json)

  it "queues the photo for a NEW account and answers at once" do
    expect { sign_in }.to have_enqueued_job(GoogleAvatarImportJob).with(kind_of(Integer), picture)
    expect(response).to have_http_status(:ok)
    expect(User.find_by(email: email).avatar).not_to be_attached # not fetched inline
  end

  it "queues nothing for a returning account, even one without an avatar" do
    create(:user, email: email, uid: email, provider: "google", confirmed_at: 1.day.ago)
    expect { sign_in }.not_to have_enqueued_job(GoogleAvatarImportJob)
    expect(response).to have_http_status(:ok)
  end

  it "queues nothing when Google sends no picture" do
    stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
      .with(query: { id_token: "tok" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { sub: "7", email: email, email_verified: "true", aud: client_id }.to_json)
    expect { sign_in }.not_to have_enqueued_job(GoogleAvatarImportJob)
    expect(response).to have_http_status(:ok)
  end

  it "a failing photo never touches the sign-in" do
    stub_request(:get, %r{googleusercontent\.com/a/}).to_return(status: 500)
    perform_enqueued_jobs(only: GoogleAvatarImportJob) { sign_in }
    expect(response).to have_http_status(:ok)
    user = User.find_by(email: email)
    expect(user).to be_active
    expect(user.avatar).not_to be_attached
  end
end
