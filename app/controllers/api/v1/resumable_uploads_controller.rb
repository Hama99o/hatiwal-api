# IDEA-9 (1.2.1, hatiwal-mobile docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §4–4.1): a video in chunks.
#
#   POST  /api/v1/uploads      { key, size, sha256, purpose }  → 201 (200 when the key is known) { upload }
#   HEAD  /api/v1/uploads/:id  → Upload-Offset / Upload-Length (where to resume after a kill)
#   PATCH /api/v1/uploads/:id  Upload-Offset: n, raw bytes     → 204 Upload-Offset: n + len
#                                                               409 + the true offset · 413 past the size
# The finished part is attached by PUT /my/listings/:id/video (or /shops/:id/video) with `upload_id`
# (VideoUploadActions). Another user's upload is a 404.
class Api::V1::ResumableUploadsController < Api::V1::BaseController
  OCTET_STREAM = "application/offset+octet-stream".freeze

  throttle to: 20, within: 1.hour, by: :user, only: :create
  # A 20 MB clip in 256 KB chunks is 80 PATCHes; a flapping EDGE line repeats some.
  throttle to: 2_000, within: 1.hour, by: :user, only: :update

  before_action :set_upload, only: %i[show update]

  def create
    authorize ResumableUpload
    existing = current_user.resumable_uploads.find_by(key: params[:key].to_s)
    return render_blue(UploadSerializer, existing) if existing

    if current_user.resumable_uploads.open.count >= ResumableUpload::MAX_OPEN
      return render_coded_error("Finish or wait for your other uploads", code: :too_many_open_uploads, status: :too_many_requests)
    end
    if params[:size].to_i > HasVideo::MAX_VIDEO_SIZE
      return render_coded_error("This video is too large (25 MB max).", code: :upload_too_large, status: :unprocessable_entity)
    end
    if ResumableUpload.open_bytes + params[:size].to_i > ResumableUpload::DISK_CAP
      return render_coded_error("The server is busy. Try again later.", code: :insufficient_storage, status: :insufficient_storage)
    end

    upload = current_user.resumable_uploads.new(params.permit(:key, :size, :sha256, :purpose))
    return render_unprocessable_entity(upload) unless upload.save

    render_blue(UploadSerializer, upload, status: :created)
  rescue ActiveRecord::RecordNotUnique
    render_blue(UploadSerializer, current_user.resumable_uploads.find_by!(key: params[:key].to_s))
  end

  # HEAD (Rails answers a HEAD with this GET action, without the body).
  def show
    authorize @upload
    offset_headers
    render_blue(UploadSerializer, @upload)
  end

  def update
    authorize @upload
    if request.content_length.to_i > ResumableUpload::MAX_CHUNK
      return render_coded_error("Chunk too large", code: :chunk_too_large, status: :payload_too_large)
    end

    @upload.append!(request.headers["Upload-Offset"].to_i, request.body.read(ResumableUpload::MAX_CHUNK + 1).to_s.b)
    offset_headers
    head :no_content
  rescue ResumableUpload::OffsetMismatch
    offset_headers(@upload.reload)
    render_coded_error("Resume from Upload-Offset", code: :offset_mismatch, status: :conflict)
  rescue ResumableUpload::TooLarge
    render_coded_error("Past the declared size", code: :upload_too_large, status: :payload_too_large)
  end

  private

  def set_upload
    @upload = policy_scope(ResumableUpload).find_by!(token: params[:id].to_s)
  end

  def offset_headers(upload = @upload)
    response.headers["Upload-Offset"] = upload.offset.to_s
    response.headers["Upload-Length"] = upload.size.to_s
    response.headers["Cache-Control"] = "no-store"
  end
end
