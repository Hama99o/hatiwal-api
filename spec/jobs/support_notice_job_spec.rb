require "rails_helper"

RSpec.describe SupportNoticeJob, type: :job do
  include ActiveJob::TestHelper

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  def notices_for(user) = Conversation.kind_support.find_by(buyer_id: user.id)&.messages.to_a

  it "tells a verified user, from Hatiwal Support, in their language" do
    user = create(:user, firstname: "Gul", preferred_language: "ps", verified: true)

    described_class.perform_now(user.id, "user_verified")

    msg = notices_for(user).sole
    expect(msg.user).to eq(User.support_account!)
    expect(msg.body).to eq(I18n.t("support.notices.user_verified", locale: :ps, name: "Gul"))
    expect(msg.body).to include("Gul")
  end

  it "falls back to the default language for an unknown one" do
    user = create(:user, verified: true)
    user.update_column(:preferred_language, "xx")

    described_class.perform_now(user.id, "user_verified")

    expect(notices_for(user).sole.body).to eq(I18n.t("support.notices.user_verified", locale: I18n.default_locale, name: user.firstname))
  end

  it "broadcasts it and queues its push, like any Support message" do
    user = create(:user, verified: true)

    expect { described_class.perform_now(user.id, "user_verified") }
      .to have_enqueued_job(BroadcastMessageJob).and have_enqueued_job(SendMessagePushJob)
  end

  it "sends nothing when the badge was switched off again before the job ran" do
    user = create(:user, verified: false)

    described_class.perform_now(user.id, "user_verified")

    expect(Conversation.kind_support.where(buyer_id: user.id)).to be_empty
  end

  it "does not post the same notice twice when the job is retried" do
    user = create(:user, verified: true)

    2.times { described_class.perform_now(user.id, "user_verified") }

    expect(notices_for(user).size).to eq(1)
  end

  it "sends nothing while admin-initiated Support is off" do
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("false")
    user = create(:user, verified: true)

    described_class.perform_now(user.id, "user_verified")

    expect(Conversation.kind_support.where(buyer_id: user.id)).to be_empty
  end

  it "refuses an unknown notice key" do
    expect { described_class.enqueue(create(:user), :nope) }.to raise_error(ArgumentError)
  end

  describe "VER-1 decisions" do
    let(:admin) { create(:admin_user) }

    it "tells a rejected user the reason, in their language" do
      request = create(:verification_request, user: create(:user, :verification_eligible, firstname: "Gul", preferred_language: "fa"))
      request.reject!(admin: admin, reason_code: "name_mismatch")

      described_class.perform_now(request.subject_id, "user_verification_rejected")

      body = notices_for(request.subject).sole.body
      expect(body).to include(I18n.t("verification.reasons.name_mismatch", locale: :fa))
      expect(body).to eq(I18n.t("support.notices.user_verification_rejected", locale: :fa, name: "Gul",
                                                                                reason: I18n.t("verification.reasons.name_mismatch", locale: :fa)))
    end

    it "tells a user their badge was removed, with the reason" do
      request = create(:verification_request)
      request.approve!(admin: admin)
      request.revoke!(admin: admin, reason_code: "other", reason_text: "Fake shop")

      described_class.perform_now(request.subject_id, "user_badge_revoked")

      expect(notices_for(request.subject).sole.body).to include("Fake shop")
    end

    it "sends no rejection once the person has applied again" do
      user = create(:user, :verification_eligible)
      create(:verification_request, user: user).reject!(admin: admin, reason_code: "photo_not_clear")
      create(:verification_request, user: user)

      described_class.perform_now(user.id, "user_verification_rejected")

      expect(notices_for(user)).to be_empty
    end
  end
end
