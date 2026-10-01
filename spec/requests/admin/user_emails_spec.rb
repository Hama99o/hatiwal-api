require "rails_helper"

RSpec.describe "Admin: email a user", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let(:user)  { create(:user, email: "zarmina@example.com") }
  let(:draft) { { subject: "About your listing", body: "سلام — ستاسو اعلان تایید شو." } }

  before do
    sign_in admin, scope: :admin_user
    ActionMailer::Base.deliveries.clear
  end

  it "shows the compose page, which sends nothing" do
    get new_admin_user_email_path(user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(user.email).and include("Preview")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "previews the real rendered email without sending or recording it" do
    post preview_admin_user_emails_path(user), params: draft

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="email-preview"').and include('id="email-send"')
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(AdminEmail.count).to eq(0)
  end

  it "rejects an empty draft at preview" do
    post preview_admin_user_emails_path(user), params: { subject: "", body: "" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('id="email-errors"')
  end

  it "sends a test ONLY to the signed-in admin, and records nothing" do
    post test_admin_user_emails_path(user), params: draft

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ admin.email ] ])
    expect(ActionMailer::Base.deliveries.last.subject).to eq("[TEST] About your listing")
    expect(AdminEmail.count).to eq(0)
    expect(response.body).to include("Test sent to #{admin.email}")
  end

  it "won't send without the preview's Send button" do
    post admin_user_emails_path(user), params: draft

    expect(AdminEmail.count).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "sends from the preview's Send button: recorded, delivered, audited, in the history" do
    perform_enqueued_jobs do
      post admin_user_emails_path(user), params: draft.merge(send: "1")
    end

    expect(response).to redirect_to(admin_user_path(user, anchor: "user-email"))
    sent = AdminEmail.last
    expect(sent).to have_attributes(user: user, admin_user: admin, status: "sent")
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ user.email ] ])
    expect(AdminAuditLog.where(action: "email_user", target: user)).to exist

    get admin_user_path(user)
    expect(response.body[%r{<table id="email-history".*?</table>}m]).to include("About your listing").and include("sent")
  end

  it "refuses to email the Support account" do
    post admin_user_emails_path(User.support_account!), params: draft.merge(send: "1")

    expect(response).to have_http_status(:unprocessable_content)
    expect(AdminEmail.count).to eq(0)
  end

  it "hides Write an email on a user who can't be emailed, and says why" do
    gone = create(:user, deleted_at: 1.day.ago)

    get admin_user_path(gone)

    expect(response.body).not_to include('id="write-email"')
    expect(response.body).to include("the account is deleted")
  end
end
