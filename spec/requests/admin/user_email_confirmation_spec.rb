require "rails_helper"

# Owner, 2026-10-08: the admin sees the email "Confirmed at" date (index, show),
# can edit it in the form, and can confirm a user in one click. Both are
# audit-logged, and the email gate (shops, verification) opens at once.
RSpec.describe "Admin confirms a user's email", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let(:user)  { create(:user, confirmed_at: nil) }

  before { sign_in admin, scope: :admin_user }

  # The gate's own refusal code, or nil once it lets the request through (the
  # empty request then fails on its params, which is not the gate's business).
  def gate_code_for(member)
    post "/api/v1/verification_requests", headers: auth_headers_for(member)
    JSON.parse(response.body)["code"]
  rescue JSON::ParserError
    nil
  end

  it "shows 'Email not confirmed' and the button on an unconfirmed user" do
    get admin_user_path(user)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Email not confirmed", "confirm-email-now")
  end

  it "Confirm email now: confirms, audit-logs, and unlocks the email gate at once" do
    expect(gate_code_for(user)).to eq("email_unconfirmed")
    expect(response).to have_http_status(:forbidden)

    freeze_time do
      patch confirm_email_admin_user_path(user)
      expect(user.reload.confirmed_at).to eq(Time.current)
    end
    expect(response).to redirect_to(admin_user_path(user))
    log = AdminAuditLog.last
    expect([ log.action, log.target, log.admin_user ]).to eq([ "confirm_email", user, admin ])
    expect(log.details).to eq(user.email)

    expect(gate_code_for(user)).not_to eq("email_unconfirmed")
    get admin_user_path(user)
    expect(response.body).to include("Email confirmed")
    expect(response.body).not_to include("confirm-email-now")
  end

  it "drops a pending change of address with its token, and says so in the audit" do
    user.update_columns(unconfirmed_email: "new@hatiwal.test", confirmation_token: "tok123")
    original = user.email

    patch confirm_email_admin_user_path(user)

    user.reload
    expect(user.email).to eq(original)
    expect([ user.unconfirmed_email, user.confirmation_token ]).to eq([ nil, nil ])
    expect(user).to be_email_confirmed
    expect(AdminAuditLog.last.details).to eq("#{original} · dropped pending change to new@hatiwal.test")
  end

  it "the form edits Confirmed at, audit-logged, and blanking it locks the gate again" do
    get edit_admin_user_path(user)
    expect(response.body).to include("user[confirmed_at]")

    patch admin_user_path(user), params: { user: { confirmed_at: "2026-10-01 09:30" } }
    expect(user.reload.confirmed_at).to be_present
    log = AdminAuditLog.last
    expect([ log.action, log.target ]).to eq([ "edit_email_confirmed_at", user ])
    expect(log.details).to start_with("not confirmed → 2026-10-01")
    expect(gate_code_for(user)).not_to eq("email_unconfirmed")

    patch admin_user_path(user), params: { user: { confirmed_at: "" } }
    expect(user.reload.confirmed_at).to be_nil
    expect(AdminAuditLog.last.details).to end_with("→ not confirmed")
    expect(gate_code_for(user)).to eq("email_unconfirmed")
  end

  it "other edits leave no confirmation audit line" do
    confirmed = create(:user, confirmed_at: 2.days.ago)

    expect { patch admin_user_path(confirmed), params: { user: { city: "Herat" } } }
      .not_to change { AdminAuditLog.where(action: "edit_email_confirmed_at").count }
  end

  it "lists the Confirmed at column on the index" do
    create(:user, confirmed_at: nil)
    get admin_users_path

    expect(response.body).to match(/Confirmed at/i)
  end
end
