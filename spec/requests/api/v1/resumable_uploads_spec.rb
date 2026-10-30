require "swagger_helper"

# IDEA-9 (1.2.1, hatiwal-mobile docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §4): a video goes up in chunks,
# and a lost answer costs one chunk, not the whole clip. tus-like:
#   POST  /api/v1/uploads      { key, size, sha256, purpose }  → the upload + its offset (idempotent on key)
#   HEAD  /api/v1/uploads/:id  → Upload-Offset                  (where to resume after a kill)
#   PATCH /api/v1/uploads/:id  Upload-Offset: n, body = bytes   → 204 Upload-Offset: n + len
# Then PUT /my/listings/:id/video { upload_id } attaches it (listing_video_resumable_spec.rb).
# §4.1 security: signed-in only, the user's own (404 otherwise), size ≤ 25 MB on every PATCH, ≤ 2 open uploads,
# throttled, a server-made path, a disk cap (507).
RSpec.describe "Resumable uploads", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:bytes) { Random.new(42).bytes(300_000) }
  let(:sha) { Digest::SHA256.hexdigest(bytes) }
  let(:create_params) { { key: SecureRandom.uuid, size: bytes.bytesize, sha256: sha, purpose: "listing_video" } }

  def json = response.parsed_body

  def start_upload(params = create_params, as: headers)
    post "/api/v1/uploads", params: params, headers: as, as: :json
    json.dig("upload", "id")
  end

  def send_chunk(id, offset, chunk, as: headers)
    patch "/api/v1/uploads/#{id}", params: chunk,
                                   headers: as.merge("Upload-Offset" => offset.to_s, "Content-Type" => "application/offset+octet-stream")
  end

  path "/api/v1/uploads" do
    post "start (or find) a resumable upload" do
      tags "Uploads"
      description "IDEA-9. `key`: the client's UUID for this upload — a retry after a lost answer returns the SAME " \
                  "upload and its current offset. `size` ≤ 25 MB, `sha256` of the whole file, `purpose`: listing_video | " \
                  "shop_video. At most 2 open uploads per user (429 too_many_open_uploads); the server's storage for " \
                  "parts is capped (507 insufficient_storage)."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client, in: :header, type: :string, required: true
      parameter name: :uid, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object, required: %w[key size sha256 purpose],
        properties: { key: { type: :string }, size: { type: :integer }, sha256: { type: :string },
                      purpose: { type: :string, enum: %w[listing_video shop_video] } }
      }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }
      let(:body) { create_params }

      response "201", "started" do
        schema type: :object, properties: { upload: { type: :object, properties: {
          id: { type: :string }, offset: { type: :integer }, size: { type: :integer }
        }, required: %w[id offset size] } }

        run_test! do
          expect(json["upload"]).to include("offset" => 0, "size" => bytes.bytesize)
          expect(json.dig("upload", "id")).to match(/\A[A-Za-z0-9_-]{20,}\z/)
        end
      end

      response "401", "signed in only" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid) { nil }

        run_test!
      end

      response "422", "over 25 MB" do
        let(:body) { create_params.merge(size: 25.megabytes + 1) }

        run_test! { expect(json["code"]).to eq("upload_too_large") }
      end
    end
  end

  describe "create" do
    it "is idempotent on the client key: the same upload and its current offset" do
      id = start_upload
      send_chunk(id, 0, bytes.byteslice(0, 100_000))

      again = start_upload

      expect(response).to have_http_status(:ok)
      expect(again).to eq(id)
      expect(json.dig("upload", "offset")).to eq(100_000)
    end

    it "refuses a size of 0, a bad checksum or an unknown purpose" do
      [ { size: 0 }, { sha256: "nope" }, { purpose: "avatar" } ].each do |bad|
        post "/api/v1/uploads", params: create_params.merge(bad), headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity), bad.inspect
      end
    end

    it "allows at most 2 open uploads per user" do
      2.times { start_upload(create_params.merge(key: SecureRandom.uuid)) }

      post "/api/v1/uploads", params: create_params.merge(key: SecureRandom.uuid), headers: headers, as: :json

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("too_many_open_uploads")
    end

    it "507 when the parts already on the server would pass the disk cap" do
      stub_const("ResumableUpload::DISK_CAP", 500_000)
      start_upload(create_params.merge(key: SecureRandom.uuid, size: 400_000))

      post "/api/v1/uploads", params: create_params.merge(key: SecureRandom.uuid), headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:insufficient_storage)
      expect(json["code"]).to eq("insufficient_storage")
    end

    it "keeps the part under storage/uploads with a server-made name (never the client's)" do
      id = start_upload(create_params.merge(key: "../../etc/passwd"))
      upload = ResumableUpload.find_by!(token: id)

      expect(upload.part_path.to_s).to start_with(ResumableUpload::DIR.to_s)
      expect(upload.part_path.basename.to_s).to eq("#{id}.part")
      expect(upload.part_path.to_s).not_to include("passwd")
    end
  end

  path "/api/v1/uploads/{id}" do
    parameter name: :id, in: :path, type: :string

    patch "append a chunk" do
      tags "Uploads"
      description "Body: the raw bytes (application/offset+octet-stream). `Upload-Offset` must equal the server's " \
                  "offset (409 + the true offset otherwise); the chunk may never pass the declared size (413). " \
                  "204 with the new Upload-Offset."
      consumes "application/offset+octet-stream"
      parameter name: :"Upload-Offset", in: :header, type: :integer, required: true
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client, in: :header, type: :string, required: true
      parameter name: :uid, in: :header, type: :string, required: true

      response "204", "appended" do
        let(:id) { start_upload }
        let(:"Upload-Offset") { 0 }
        let(:"access-token") { headers["access-token"] }
        let(:client) { headers["client"] }
        let(:uid) { headers["uid"] }

        it "appends and answers the new offset" do
          send_chunk(id, 0, bytes.byteslice(0, 120_000))

          expect(response).to have_http_status(:no_content)
          expect(response.headers["Upload-Offset"]).to eq("120000")
        end
      end
    end
  end

  describe "HEAD and PATCH" do
    let!(:id) { start_upload }

    it "HEAD answers where to resume (after a kill)" do
      send_chunk(id, 0, bytes.byteslice(0, 50_000))

      head "/api/v1/uploads/#{id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["Upload-Offset"]).to eq("50000")
      expect(response.headers["Upload-Length"]).to eq(bytes.bytesize.to_s)
    end

    it "the whole file in chunks, byte for byte" do
      [ 0, 100_000, 200_000 ].each { |off| send_chunk(id, off, bytes.byteslice(off, 100_000)) }

      expect(response.headers["Upload-Offset"]).to eq(bytes.bytesize.to_s)
      expect(File.binread(ResumableUpload.find_by!(token: id).part_path)).to eq(bytes)
    end

    it "409 + the true offset when the client is behind or ahead (a lost answer)" do
      send_chunk(id, 0, bytes.byteslice(0, 100_000))
      send_chunk(id, 0, bytes.byteslice(0, 100_000)) # the same chunk again: its first answer was lost

      expect(response).to have_http_status(:conflict)
      expect(response.headers["Upload-Offset"]).to eq("100000")
      expect(File.size(ResumableUpload.find_by!(token: id).part_path)).to eq(100_000)
    end

    it "413 when a chunk would pass the declared size; nothing is written" do
      send_chunk(id, 0, bytes + "x")

      expect(response).to have_http_status(:payload_too_large)
      expect(File.size?(ResumableUpload.find_by!(token: id).part_path).to_i).to eq(0)
    end

    it "404 for another user's upload, for HEAD and PATCH alike (no existence leak)" do
      other = auth_headers_for(create(:user))

      head "/api/v1/uploads/#{id}", headers: other
      expect(response).to have_http_status(:not_found)
      send_chunk(id, 0, bytes.byteslice(0, 10), as: other)
      expect(response).to have_http_status(:not_found)
    end

    it "404 for a made-up or path-like id" do
      head "/api/v1/uploads/..%2F..%2Fetc%2Fpasswd", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe ResumableUploadSweepJob do
    it "deletes uploads (and their parts) left for more than 24 hours; recent ones stay" do
      old_id = start_upload(create_params.merge(key: SecureRandom.uuid))
      send_chunk(old_id, 0, bytes.byteslice(0, 10))
      old = ResumableUpload.find_by!(token: old_id)
      old.update_columns(updated_at: 25.hours.ago)
      fresh = ResumableUpload.find_by!(token: start_upload(create_params.merge(key: SecureRandom.uuid)))

      described_class.perform_now

      expect(ResumableUpload.exists?(old.id)).to be(false)
      expect(File.exist?(old.part_path)).to be(false)
      expect(ResumableUpload.exists?(fresh.id)).to be(true)
    end
  end
end
