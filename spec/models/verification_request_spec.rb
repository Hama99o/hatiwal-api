require "rails_helper"

RSpec.describe VerificationRequest, type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user) }
  let(:request) { create(:verification_request) }
  let(:user) { request.subject }

  it "has a valid factory" do
    expect(build(:verification_request)).to be_valid
    expect(build(:verification_request, :two_sided)).to be_valid
  end

  it "accepts only users as subjects for now" do
    expect(described_class::SUBJECT_TYPES).to eq([ "User" ])
  end

  describe "#approve!" do
    it "sets the badge, saves the checklist and queues the verified message" do
      expect { request.approve!(admin: admin, checklist: { "photo_clear" => "1", "name_matches" => "1" }) }
        .to have_enqueued_job(SupportNoticeJob).with(user.id, "user_verified")
      expect(user.reload).to be_verified
      expect(request.reload).to have_attributes(status: "approved", decided_by: admin)
      expect(request.checklist).to eq("photo_clear" => true, "name_matches" => true, "selfie_matches" => false, "no_bad_history" => false)
    end

    it "refuses a request that is not waiting" do
      request.reject!(admin: admin, reason_code: "photo_not_clear")
      expect { request.approve!(admin: admin) }.to raise_error(ArgumentError)
    end
  end

  describe "#reject!" do
    it "records the reason and queues the rejected message" do
      expect { request.reject!(admin: admin, reason_code: "name_mismatch") }
        .to have_enqueued_job(SupportNoticeJob).with(user.id, "user_verification_rejected")
      expect(request.reload).to have_attributes(status: "rejected", reason_code: "name_mismatch", reason_text: nil)
      expect(user.reload).not_to be_verified
    end

    it "needs the text for other, and sends it as typed" do
      expect { request.reject!(admin: admin, reason_code: "other") }.to raise_error(ArgumentError)
      request.reject!(admin: admin, reason_code: "other", reason_text: "Wrong country")
      expect(request.reason_for(:ps)).to eq("Wrong country")
    end

    it "refuses an unknown reason" do
      expect { request.reject!(admin: admin, reason_code: "ugly") }.to raise_error(ArgumentError)
    end
  end

  describe "#revoke!" do
    it "removes the badge and queues the revoked message" do
      request.approve!(admin: admin)
      expect { request.revoke!(admin: admin, reason_code: "policy_violation") }
        .to have_enqueued_job(SupportNoticeJob).with(user.id, "user_badge_revoked")
      expect(user.reload).not_to be_verified
      expect(request.reload).to be_revoked
    end
  end

  describe ".revoke_badge!" do
    it "revokes a badge switched on by hand, leaving a decided row for the card" do
      manual = create(:user, :verified)
      result = described_class.revoke_badge!(manual, admin: admin, reason_code: "policy_violation")
      expect(result).to be_revoked
      expect(manual.reload).not_to be_verified
      expect(VerificationStatus.new(manual).state).to eq("revoked")
    end
  end

  describe "#cancel!" do
    it "deletes the files at once" do
      request.cancel!
      expect(request.reload).to be_cancelled
      expect(request.files_count).to eq(0)
      expect(request.files_purged_at).to be_present
    end
  end

  describe "document tokens" do
    it "work for this request's files and expire after 5 minutes" do
      token = request.document_token(:front)
      expect(request.blob_for_token(token)).to eq(request.front.blob)
      expect(create(:verification_request).blob_for_token(token)).to be_nil
      travel 6.minutes do
        expect(request.blob_for_token(token)).to be_nil
      end
    end

    it "are not accepted by the public blob lookup" do
      expect(ActiveStorage::Blob.find_signed(request.document_token(:front))).to be_nil
    end
  end

  it "has every reason translated in all four locales" do
    (described_class::REJECT_REASONS + described_class::REVOKE_REASONS).uniq.each do |code|
      User::SUPPORTED_LANGUAGES.each do |locale|
        expect(I18n.exists?("verification.reasons.#{code}", locale.to_sym)).to be(true), "#{locale}: #{code}"
      end
    end
  end

  it "has the verification notices in all four locales" do
    %w[user_verification_rejected user_badge_revoked].each do |key|
      User::SUPPORTED_LANGUAGES.each do |locale|
        expect(I18n.t("support.notices.#{key}", locale: locale.to_sym, name: "X", reason: "Y")).to include("Y")
      end
    end
  end

  it "has its validation messages in all four locales" do
    User::SUPPORTED_LANGUAGES.each do |locale|
      I18n.with_locale(locale) do
        request = described_class.new
        request.errors.add(:subject, :already_verified)
        request.errors.add(:subject, :not_eligible, missing: "avatar")
        expect(request.errors.full_messages.join).not_to include("Translation missing"), locale
        expect(request.errors.full_messages.last).to include("avatar")
      end
    end
  end

  it "has the indexes the queue, the status card and the purge job filter on (scale)" do
    names = ActiveRecord::Base.connection.indexes(:verification_requests).map(&:name)
    expect(names).to include("index_verification_requests_on_subject",
                             "index_verification_requests_one_open_per_subject",
                             "index_verification_requests_on_status_and_created_at",
                             "index_verification_requests_purgeable")
  end

  describe "when the account is deleted (User#anonymize_account!)" do
    it "cancels the open request, deletes every photo and blanks the document details" do
      user = create(:user, :verification_eligible)
      old = create(:verification_request, :two_sided, user: user)
      old.reject!(admin: admin, reason_code: "photo_not_clear")
      waiting = create(:verification_request, user: user)
      keys = [ old, waiting ].flat_map { |r| r.attached_files.map { |n| r.public_send(n).blob.key } }

      user.anonymize_account!

      [ old.reload, waiting.reload ].each do |r|
        expect(r.files_count).to eq(0)
        expect(r).to have_attributes(name_on_document: nil, document_last4: nil)
        expect(r.files_purged_at).to be_present
      end
      expect(waiting).to be_cancelled
      expect(old).to be_rejected
      expect(described_class.requested).not_to exist
      keys.each { |key| expect(ActiveStorage::Blob.service.exist?(key)).to be(false) }
      expect(user.reload).not_to be_verified
    end
  end
end
