require "rails_helper"

RSpec.describe PurgeVerificationFilesJob, type: :job do
  let(:admin) { create(:admin_user) }

  it "deletes the photos 90 days after the decision and keeps the decision" do
    old = create(:verification_request, :two_sided)
    old.reject!(admin: admin, reason_code: "photo_not_clear", checklist: { "photo_clear" => "0" })
    old.update_columns(decided_at: 91.days.ago)
    blob_keys = old.attached_files.map { |name| old.public_send(name).blob.key }

    recent = create(:verification_request)
    recent.reject!(admin: admin, reason_code: "photo_not_clear")
    waiting = create(:verification_request)

    described_class.perform_now

    old.reload
    expect(old.files_count).to eq(0)
    expect(old.files_purged_at).to be_present
    expect(old).to have_attributes(status: "rejected", reason_code: "photo_not_clear")
    expect(old.checklist).to include("photo_clear" => false)
    blob_keys.each { |key| expect(ActiveStorage::Blob.service.exist?(key)).to be(false) }

    expect(recent.reload.files_count).to eq(3) # e-Tazkira front + back + selfie
    expect(waiting.reload.files_count).to eq(3)
  end
end
