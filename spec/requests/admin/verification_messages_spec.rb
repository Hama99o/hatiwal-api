require "rails_helper"

# The verification queue end to end: Approve / Reject from the admin card write
# a Support message to the person (or the shop's OWNER) in THEIR language —
# congratulations on approve, the reason + "try again" on reject — and the
# admin is told honestly whether that message can be delivered.
RSpec.describe "Admin verification — decisions and Support messages", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }

  before do
    sign_in admin, scope: :admin_user
    allow(Conversation).to receive(:admin_initiate_enabled?).and_return(true)
  end

  def support_text_for(user)
    Conversation.kind_support.find_by(buyer_id: user.id)&.messages&.order(:id)&.last&.body
  end

  def decide(request, action, params = {})
    perform_enqueued_jobs(only: SupportNoticeJob) do
      patch public_send("#{action}_admin_verification_request_path", request), params: params
    end
  end

  describe "a person" do
    let(:request_record) { create(:verification_request, :two_sided) }
    let(:user) { request_record.subject }

    it "approve: verified, congratulated in Pashto, flash says the message goes out" do
      user.update!(preferred_language: "ps")
      decide(request_record, :approve, checklist: { photo_clear: "1" })
      expect(user.reload).to be_verified
      expect(support_text_for(user)).to include("مبارک شه")
      expect(flash[:notice]).to include("is verified", "gets a Support message in Pashto")
    end

    it "reject: the reason in Dari and how to try again; the request can be sent again" do
      user.update!(preferred_language: "fa")
      decide(request_record, :reject, reason_code: "photo_not_clear")
      text = support_text_for(user)
      expect(text).to include(I18n.t("verification.reasons.photo_not_clear", locale: :fa))
      expect(text).to include("پروفایل")
      expect(flash[:notice]).to include("can try again", "in Dari")
      expect(VerificationStatus.new(user.reload).state).to eq("rejected")
    end

    it "reject with Other: the admin's own words reach the person" do
      user.update!(preferred_language: "en")
      decide(request_record, :reject, reason_code: "other", reason_text: "The photo is upside down")
      expect(support_text_for(user)).to include("Reason: The photo is upside down", "try again")
    end

    it "reject with no reason: nothing decided, a clear alert" do
      decide(request_record, :reject, reason_code: "")
      expect(request_record.reload).to be_requested
      expect(flash[:alert]).to eq("choose a reason first")
      expect(support_text_for(user)).to be_nil
    end

    it "says plainly when the Support gate holds the message back" do
      allow(Conversation).to receive(:admin_initiate_enabled?).and_return(false)
      get admin_verification_request_path(request_record)
      expect(response.body).to include("verify-message-note", "No Support message can reach")
      decide(request_record, :approve)
      expect(user.reload).to be_verified
      expect(flash[:notice]).to include("No Support message sent")
      expect(support_text_for(user)).to be_nil
    end
  end

  describe "a shop" do
    let(:request_record) { create(:shop_verification_request) }
    let(:shop) { request_record.subject }
    let(:owner) { shop.owner }

    it "approve: the shop is verified, the OWNER is congratulated in their language" do
      owner.update!(preferred_language: "fa")
      decide(request_record, :approve, checklist: { proof_valid: "1" })
      expect(shop.reload.verified?).to be(true)
      expect(owner.reload.verified).to be(false)
      expect(support_text_for(owner)).to include("تبریک", shop.name)
      expect(flash[:notice]).to include("#{owner.full_name} gets a Support message in Dari")
    end

    it "reject: the owner gets the proof reason in Pashto and where to try again" do
      owner.update!(preferred_language: "ps")
      decide(request_record, :reject, reason_code: "proof_not_accepted")
      expect(support_text_for(owner)).to include(shop.name, "د سوداګرۍ ثبوت ونه منل شو", "زما دوکان")
      expect(shop.reload.verified?).to be(false)
    end

    it "offers proof_not_accepted on a shop card only" do
      get admin_verification_request_path(request_record)
      expect(response.body).to include('value="proof_not_accepted"')
      get admin_verification_request_path(create(:verification_request))
      expect(response.body).not_to include('value="proof_not_accepted"')
    end
  end

  describe "the Users / Shops filter" do
    let!(:person_request) { create(:verification_request) }
    let!(:shop_request) { create(:shop_verification_request) }

    it "keeps each kind apart and shows what waits on each tab" do
      get admin_verification_requests_path(kind: "users")
      expect(response.body).to include("Users (1 waiting)", "Shops (1 waiting)", person_request.subject.full_name)
      expect(response.body).not_to include(shop_request.subject.name)
      expect(response.body).to include("<th>Person</th>")

      get admin_verification_requests_path(kind: "shops")
      expect(response.body).to include(shop_request.subject.name, "<th>Shop</th>")
      expect(response.body).not_to include(person_request.subject.full_name)
    end

    it "keeps the kind on the status filters and on the card's way back" do
      get admin_verification_requests_path(kind: "shops")
      expect(response.body).to include(CGI.escapeHTML(admin_verification_requests_path(status: "approved", kind: "shops")))
      get admin_verification_request_path(shop_request)
      expect(response.body).to include(admin_verification_requests_path(kind: "shops"))
    end

    it "opens on Shops from the nav when only shops are waiting" do
      person_request.reject!(admin: admin, reason_code: "photo_not_clear")
      get admin_verification_requests_path
      expect(response.body).to include(shop_request.subject.name)
    end

    it "after the last shop decision, goes back to the Shops queue, not Users" do
      decide(shop_request, :approve)
      expect(response).to redirect_to(admin_verification_requests_path(kind: "shops"))
    end
  end
end
