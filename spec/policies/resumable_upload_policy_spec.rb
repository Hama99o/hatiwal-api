require "rails_helper"

# IDEA-9: an upload is its user's alone (the scope hides it from anyone else -> 404).
RSpec.describe ResumableUploadPolicy do
  let(:upload) { create(:resumable_upload) }
  let(:stranger) { create(:user) }

  it "only the owner may see or append, and only while it is open" do
    expect(described_class.new(upload.user, upload).show?).to be(true)
    expect(described_class.new(upload.user, upload).update?).to be(true)
    expect(described_class.new(stranger, upload).show?).to be(false)
    upload.update!(status: :completed)
    expect(described_class.new(upload.user, upload).update?).to be(false)
  end

  it "the scope is the user's own uploads; nothing for a guest" do
    upload
    expect(described_class::Scope.new(stranger, ResumableUpload).resolve).to be_empty
    expect(described_class::Scope.new(upload.user, ResumableUpload).resolve).to contain_exactly(upload)
    expect(described_class::Scope.new(nil, ResumableUpload).resolve).to be_empty
  end
end
