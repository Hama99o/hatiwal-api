require "rails_helper"

# IDEA-9 (1.2.1, docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §4–4.1): finalize a chunked upload into the
# listing's video. PUT /my/listings/:id/video with `upload_id` (and the small poster + duration as today) instead
# of the whole clip. Finalize checks the size, the sha256 and the container by its BYTES, then runs the same video
# validations as today; the part is deleted afterwards. Today's one-shot PUT (old apps) is unchanged.
RSpec.describe "Listing video from a resumable upload", type: :request do
  let(:seller) { create(:user) }
  let(:headers) { auth_headers_for(seller) }
  let(:listing) { create(:listing, :active, :with_image, user: seller) }
  let(:mp4) { File.binread(Rails.root.join("spec/fixtures/files/test_video.mp4")) }
  let(:poster) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }

  # Uploads `bytes` in 7 KB chunks (the last answer of each is real) and returns the upload's id.
  def upload(bytes, as: headers, sha256: Digest::SHA256.hexdigest(bytes), size: bytes.bytesize, send: bytes.bytesize)
    post "/api/v1/uploads", params: { key: SecureRandom.uuid, size: size, sha256: sha256, purpose: "listing_video" },
                            headers: as, as: :json
    id = response.parsed_body.dig("upload", "id")
    (0...send).step(7_000) do |off|
      patch "/api/v1/uploads/#{id}", params: bytes.byteslice(off, [ 7_000, send - off ].min),
                                     headers: as.merge("Upload-Offset" => off.to_s, "Content-Type" => "application/offset+octet-stream")
    end
    id
  end

  def finalize(id, as: headers)
    put "/api/v1/my/listings/#{listing.id}/video", params: { upload_id: id, duration_s: 2, poster: poster }, headers: as
  end

  it "attaches the uploaded clip, with its poster and duration, and deletes the part" do
    id = upload(mp4)
    part = ResumableUpload.find_by!(token: id).part_path

    finalize(id)

    expect(response).to have_http_status(:ok)
    expect(listing.reload.video.blob.download).to eq(mp4)
    expect(listing.video.blob.content_type).to eq("video/mp4")
    expect(listing.video_duration_s).to eq(2)
    expect(listing.video_poster).to be_attached
    expect(File.exist?(part)).to be(false)
    expect(ResumableUpload.find_by!(token: id)).to be_completed
  end

  it "a second finalize (its answer was lost) returns the listing, the same video, nothing new" do
    id = upload(mp4)
    finalize(id)
    blob_id = listing.reload.video.blob.id

    expect { finalize(id) }.not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:ok)
    expect(listing.reload.video.blob.id).to eq(blob_id)
  end

  it "refuses an incomplete upload" do
    id = upload(mp4, send: 14_000)

    finalize(id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("upload_incomplete")
    expect(listing.reload.video).not_to be_attached
  end

  it "refuses a file whose sha256 is not the declared one" do
    id = upload(mp4, sha256: Digest::SHA256.hexdigest("something else"))

    finalize(id)

    expect(response.parsed_body["code"]).to eq("upload_checksum_mismatch")
    expect(listing.reload.video).not_to be_attached
  end

  it "checks the container by its bytes: a text file called a video is refused" do
    id = upload("this is not a video" * 100)

    finalize(id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("upload_not_a_video")
    expect(listing.reload.video).not_to be_attached
    expect(ResumableUpload.find_by(token: id)).to be_nil
    expect(Dir.glob(ResumableUpload::DIR.join("#{id}.part"))).to be_empty
  end

  it "an upload started for a shop video cannot become a listing's video (404)" do
    post "/api/v1/uploads", params: { key: SecureRandom.uuid, size: mp4.bytesize, sha256: Digest::SHA256.hexdigest(mp4), purpose: "shop_video" },
                            headers: headers, as: :json

    finalize(response.parsed_body.dig("upload", "id"))

    expect(response).to have_http_status(:not_found)
  end

  it "404 for another user's upload" do
    other = create(:user)
    id = upload(mp4, as: auth_headers_for(other))

    finalize(id)

    expect(response).to have_http_status(:not_found)
    expect(listing.reload.video).not_to be_attached
  end

  it "today's one-shot multipart PUT still works (old apps)" do
    put "/api/v1/my/listings/#{listing.id}/video",
        params: { video: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_video.mp4"), "video/mp4"), duration_s: 2 },
        headers: headers

    expect(response).to have_http_status(:ok)
    expect(listing.reload.video).to be_attached
  end

  it "app_config says whether the server takes resumable uploads (the kill switch)" do
    get "/api/v1/app_config"
    expect(response.parsed_body.dig("features", "resumable_uploads")).to be(true)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("RESUMABLE_UPLOADS_ENABLED").and_return("0")
    get "/api/v1/app_config"
    expect(response.parsed_body.dig("features", "resumable_uploads")).to be(false)
  end
end
