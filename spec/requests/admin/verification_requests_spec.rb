require "rails_helper"

# VER-1 admin queue: decide by hand, every action (and every photo opened) in
# the audit log, documents only through short-lived tokens.
RSpec.describe "Admin verification queue", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user) }
  let(:request_record) { create(:verification_request, :two_sided) }
  let(:user) { request_record.subject }

  before { sign_in admin, scope: :admin_user }

  it "needs an admin session" do
    sign_out :admin_user
    get admin_verification_requests_path
    expect(response).to redirect_to(new_admin_user_session_path)
  end

  it "lists waiting requests with counts per status" do
    request_record
    create(:verification_request).reject!(admin: admin, reason_code: "photo_not_clear")
    get admin_verification_requests_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Waiting (1)", "Rejected (1)", user.full_name)
  end

  it "shows the card with the three photos through expiring document links" do
    get admin_verification_request_path(request_record)
    expect(response).to have_http_status(:ok)
    expect(response.body.scan(%r{/admin/verification_requests/#{request_record.id}/document/}).size).to be >= 3
    # Never a public Active Storage link to a document (the avatar's is fine).
    request_record.attached_files.each do |name|
      expect(response.body).not_to include(request_record.public_send(name).blob.signed_id)
    end
  end

  describe "document" do
    it "serves the photo and logs who looked" do
      token = request_record.document_token(:selfie)
      expect { get document_admin_verification_request_path(request_record, token: token) }
        .to change { AdminAuditLog.where(action: "verification_document_view", target: request_record, admin_user: admin).count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(AdminAuditLog.last.details).to eq("selfie")
    end

    it "refuses an expired token" do
      token = request_record.document_token(:front)
      travel 6.minutes do
        get document_admin_verification_request_path(request_record, token: token)
      end
      expect(response).to have_http_status(:not_found)
    end

    it "refuses another request's token" do
      other = create(:verification_request)
      get document_admin_verification_request_path(request_record, token: other.document_token(:front))
      expect(response).to have_http_status(:not_found)
    end

    it "refuses an avatar's public signed id" do
      get document_admin_verification_request_path(request_record, token: user.avatar.blob.signed_id)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "approves with the checklist, logs it and queues the verified message" do
    expect do
      patch approve_admin_verification_request_path(request_record), params: { checklist: { photo_clear: "1", name_matches: "1" } }
    end.to have_enqueued_job(SupportNoticeJob).with(user.id, "user_verified")
    expect(user.reload).to be_verified
    expect(request_record.reload.checklist).to include("photo_clear" => true, "selfie_matches" => false)
    expect(AdminAuditLog.where(action: "verification_approve", target: request_record).sole.details).to include("photo_clear")
  end

  it "rejects with a preset reason, logs it and queues the rejected message" do
    expect do
      patch reject_admin_verification_request_path(request_record), params: { reason_code: "selfie_mismatch" }
    end.to have_enqueued_job(SupportNoticeJob).with(user.id, "user_verification_rejected")
    expect(request_record.reload).to have_attributes(status: "rejected", reason_code: "selfie_mismatch")
    expect(AdminAuditLog.where(action: "verification_reject", target: request_record).sole.details).to eq("selfie_mismatch")
  end

  # Reject is a formaction button on the Approve form. With CSRF on, the form's
  # token must be the session one, or posting it to Reject raised
  # InvalidAuthenticityToken (owner, 2026-10-07).
  describe "deciding through the real form, with CSRF protection on" do
    around do |example|
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    def form_token
      get admin_verification_request_path(request_record)
      form = response.body[%r{<form[^>]*id="verification-decision".*?</form>}m]
      expect(form).to include(%(formaction="#{reject_admin_verification_request_path(request_record)}"))
      form[/name="authenticity_token" value="([^"]+)"/, 1]
    end

    it "Reject works with the token the form carries, and queues the Support notice" do
      token = form_token
      expect do
        patch reject_admin_verification_request_path(request_record),
              params: { authenticity_token: token, reason_code: "selfie_mismatch", checklist: { photo_clear: "1" } }
      end.to have_enqueued_job(SupportNoticeJob).with(user.id, "user_verification_rejected")
      expect(request_record.reload).to have_attributes(status: "rejected", reason_code: "selfie_mismatch")
    end

    it "Approve still works with the same token" do
      token = form_token
      patch approve_admin_verification_request_path(request_record), params: { authenticity_token: token }
      expect(request_record.reload.status).to eq("approved")
    end
  end

  it "does not reject without a reason" do
    patch reject_admin_verification_request_path(request_record), params: { reason_code: "" }
    expect(request_record.reload).to be_requested
    expect(flash[:alert]).to be_present
  end

  it "revokes an approved badge" do
    request_record.approve!(admin: admin)
    expect do
      patch revoke_admin_verification_request_path(request_record), params: { reason_code: "other", reason_text: "Fake name" }
    end.to have_enqueued_job(SupportNoticeJob).with(user.id, "user_badge_revoked")
    expect(user.reload).not_to be_verified
    expect(AdminAuditLog.where(action: "verification_revoke").sole.details).to eq("other: Fake name")
  end

  it "revokes a hand-switched badge from the user page" do
    manual = create(:user, :verified)
    post revoke_badge_admin_verification_requests_path(user_id: manual.id), params: { reason_code: "policy_violation" }
    expect(response).to redirect_to(admin_user_path(manual))
    expect(manual.reload).not_to be_verified
    expect(AdminAuditLog.where(action: "verification_revoke").count).to eq(1)
  end

  it "shows the verification panel and nav badge on the user page" do
    request_record
    get admin_user_path(user)
    expect(response.body).to include("user-verification", "Verification waiting", "nav-verifications")
  end

  it "says on the dashboard how many are waiting" do
    request_record
    get admin_root_path
    expect(response.body).to include("attention-verifications", "1 verification request waiting")
  end

  describe "the ID number" do
    it "shows ••••last4, and the full number only on Show number, logged and not cached" do
      get admin_verification_request_path(request_record)
      expect(response.body).to include("••••4821")
      expect(response.body).not_to include("1234564821")

      expect { post reveal_number_admin_verification_request_path(request_record) }
        .to change { AdminAuditLog.where(action: "verification_number_view", target: request_record, admin_user: admin).count }.by(1)
      expect(response.body).to include("1234564821")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "warns when the same number is on another account, with blocked shown" do
      other = create(:verification_request, document_number: request_record.document_number)
      other.subject.update!(status: :banned)
      get admin_verification_request_path(request_record)
      expect(response.body).to include("verify-same-number", "##{other.subject.id}", "blocked")
    end
  end
end
