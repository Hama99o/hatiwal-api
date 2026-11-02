require "rails_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 8): the decision area
# of a verification request. Approve and Reject are two clear actions; Reject
# needs a reason (plain labels, "Other" text only when picked, a preview of what
# the person gets); a missing reason is an inline error at the field, with what
# was typed kept — never a crash or a blank 422. Same for Revoke and for shops.
RSpec.describe "Admin verification — the decision area", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:person) { create(:user, :verification_eligible, firstname: "Fatima", lastname: "Karimi", preferred_language: "fa") }
  let(:request_record) { create(:verification_request, :two_sided, user: person) }

  before { sign_in admin, scope: :admin_user }

  def body = response.body

  describe "the page" do
    it "shows Approve and Reject as two separate boxes, the checklist count, and the reasons in plain words" do
      get admin_verification_request_path(request_record)
      expect(body).to include('id="verify-approve-box"', 'id="verify-reject-box"', 'id="verify-check-count"')
      expect(body).to include("0 of 4 checked")
      expect(body).to include(I18n.t("verification.reasons.photo_not_clear", locale: :en))
      expect(body).not_to include('value="proof_not_accepted"') # shops only
      # The "Other" field is hidden until "Other" is picked; the preview is in the person's language.
      expect(body).to match(/id="verify-reject-other"[^>]*hidden/)
      expect(body).to include(I18n.t("verification.reasons.photo_not_clear", locale: :fa).to_json[1..-2])
      expect(body).to include("Fatima will get:")
    end
  end

  describe "Reject" do
    it "without a reason: the same page, an error at the reason, the checklist kept, nothing decided" do
      patch reject_admin_verification_request_path(request_record),
            params: { reason_code: "", checklist: { photo_clear: "1", name_matches: "1" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include("Choose a reason: Fatima Karimi is told why, in their language.")
      expect(body).to match(/id="verify-reject-box"[^>]*open/)
      expect(body).to include("2 of 4 checked")
      expect(body).to match(/id="checklist-photo_clear"[^>]*checked|checked[^>]*id="checklist-photo_clear"/)
      expect(request_record.reload).to be_requested
    end

    it "Other without its text: an error at the text, the Other field shown and Other kept selected" do
      patch reject_admin_verification_request_path(request_record), params: { reason_code: "other", reason_text: "  " }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include("Write the reason for “Other”: it is sent to Fatima Karimi as you type it.")
      expect(body).not_to match(/id="verify-reject-other"[^>]*hidden/)
      expect(body).to match(/<option selected="selected" value="other">/)
      # No empty “” preview while "Other" has no text yet.
      expect(body).to match(/id="verify-reject-preview"[^>]*hidden/)
      expect(request_record.reload).to be_requested
    end

    it "a shop-only reason on a person's request is refused at the field" do
      patch reject_admin_verification_request_path(request_record), params: { reason_code: "proof_not_accepted" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include("That reason isn't available here.")
    end

    it "happy path: rejected, the person told, the next request opened" do
      waiting = create(:verification_request, :two_sided)
      expect do
        patch reject_admin_verification_request_path(request_record), params: { reason_code: "other", reason_text: "The selfie is too dark" }
      end.to have_enqueued_job(SupportNoticeJob).with(person.id, "user_verification_rejected")
      expect(request_record.reload).to have_attributes(status: "rejected", reason_code: "other", reason_text: "The selfie is too dark")
      expect(response).to redirect_to(admin_verification_request_path(waiting))
      expect(flash[:notice]).to include("Request rejected.", "Next request opened.")
    end
  end

  describe "Approve" do
    it "is never blocked by unticked boxes; the ticked ones are saved" do
      patch approve_admin_verification_request_path(request_record), params: { checklist: { photo_clear: "1" } }
      expect(request_record.reload).to have_attributes(status: "approved")
      expect(request_record.checklist).to include("photo_clear" => true, "name_matches" => false)
      expect(flash[:notice]).to include("is verified.", "No more waiting.")
    end
  end

  describe "Revoke" do
    before { request_record.approve!(admin: admin) }

    it "without a reason: the same page with the error at the reason, the badge kept" do
      patch revoke_admin_verification_request_path(request_record), params: { reason_code: "" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include("Choose a reason: Fatima Karimi is told why")
      expect(person.reload).to be_verified
    end

    it "happy path: revoked with a preset reason" do
      patch revoke_admin_verification_request_path(request_record), params: { reason_code: "policy_violation" }
      expect(response).to redirect_to(admin_verification_request_path(request_record))
      expect(person.reload).not_to be_verified
    end

    it "from the user page: a friendly alert for Other without text, and the badge kept" do
      post revoke_badge_admin_verification_requests_path(user_id: person.id), params: { reason_code: "other" }
      expect(response).to redirect_to(admin_user_path(person, anchor: "revoke-badge"))
      expect(flash[:alert]).to include("Badge not removed: Write the reason for “Other”")
      expect(person.reload).to be_verified
    end
  end

  describe "a shop's request" do
    let(:shop_request) { create(:shop_verification_request) }
    let(:shop) { shop_request.subject }

    it "offers proof_not_accepted, previews it for the owner, and rejects with it" do
      get admin_verification_request_path(shop_request)
      expect(body).to include('value="proof_not_accepted"', "#{shop.owner.firstname} will get:")

      patch reject_admin_verification_request_path(shop_request), params: { reason_code: "proof_not_accepted" }
      expect(shop_request.reload).to have_attributes(status: "rejected", reason_code: "proof_not_accepted")
    end

    it "Remove badge from the shop page: a friendly alert without a reason" do
      shop_request.approve!(admin: admin)
      post remove_badge_admin_shop_path(shop), params: { reason_code: "" }
      expect(flash[:alert]).to include("Badge not removed: Choose a reason")
      expect(shop.reload.verified?).to be(true)
    end
  end

  describe "through the real form, with CSRF protection on" do
    around do |example|
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    def token_from(path, form_id)
      get path
      form = body[%r{<form[^>]*id="#{form_id}".*?</form>}m]
      form[/name="authenticity_token" value="([^"]+)"/, 1]
    end

    it "an error comes back as the page (422) and a corrected submit then works" do
      token = token_from(admin_verification_request_path(request_record), "verification-decision")
      patch reject_admin_verification_request_path(request_record), params: { authenticity_token: token, reason_code: "" }
      expect(response).to have_http_status(:unprocessable_entity)

      token = body[%r{<form[^>]*id="verification-decision".*?</form>}m][/name="authenticity_token" value="([^"]+)"/, 1]
      patch reject_admin_verification_request_path(request_record),
            params: { authenticity_token: token, reason_code: "photo_not_clear" }
      expect(request_record.reload).to be_rejected
    end

    it "Revoke works with the token its own form carries" do
      request_record.approve!(admin: admin)
      token = token_from(admin_verification_request_path(request_record), "verify-revoke-form")
      patch revoke_admin_verification_request_path(request_record), params: { authenticity_token: token, reason_code: "name_mismatch" }
      expect(person.reload).not_to be_verified
    end
  end
end
