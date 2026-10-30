require "rails_helper"

# IDEA-9 (1.2.1, docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §4–4.1).
RSpec.describe ResumableUpload do
  let(:upload) { create(:resumable_upload, size: 10, sha256: Digest::SHA256.hexdigest("0123456789")) }

  after { FileUtils.rm_f(upload.part_path) }

  it "appends in order, refuses a wrong offset and anything past the size" do
    expect(upload.append!(0, "0123")).to eq(4)
    expect { upload.append!(0, "0123") }.to raise_error(described_class::OffsetMismatch)
    expect { upload.append!(4, "45678901") }.to raise_error(described_class::TooLarge)
    expect(upload.append!(4, "456789")).to eq(10)
    expect(File.binread(upload.part_path)).to eq("0123456789")
  end

  it "drops a half-written chunk (a crash between the write and the offset) before appending" do
    upload.append!(0, "0123")
    File.open(upload.part_path, "ab") { |f| f.write("garbage") }

    upload.append!(4, "456789")

    expect(File.binread(upload.part_path)).to eq("0123456789")
  end

  it "the name on disk is the server's token, under DIR" do
    expect(upload.part_path.dirname).to eq(described_class::DIR)
    expect(upload.token).to match(/\A[A-Za-z0-9_-]{32}\z/)
  end

  it "validates the size (≤ 25 MB), the checksum format and the purpose" do
    expect(build(:resumable_upload, size: HasVideo::MAX_VIDEO_SIZE + 1)).not_to be_valid
    expect(build(:resumable_upload, sha256: "zz")).not_to be_valid
    expect(build(:resumable_upload, purpose: "avatar")).not_to be_valid
  end

  it "destroying it removes its part" do
    upload.append!(0, "01")
    path = upload.part_path

    upload.destroy

    expect(File.exist?(path)).to be(false)
  end
end
