# VID / SHOP-MEDIA — the two video endpoints, written once:
#
#   PUT    …/video   multipart: video (mp4/mov ≤ 25 MB), poster (image, optional),
#                    duration_s (optional) — replaces any previous video
#   DELETE …/video   removes the video and its poster
#
# Multipart through an authenticated controller, never Active Storage direct
# upload: direct uploads are closed on purpose
# (config/initializers/no_active_storage_writes.rb). The record is a HasVideo
# model; the including controller supplies:
#
#   video_record          the record (found + scoped by its own before_action)
#   authorize_video!(act) Pundit for :update / :destroy
#   render_video_record   the record's JSON after a change
module VideoUploadActions
  extend ActiveSupport::Concern

  included do
    # A retry re-sends the whole file, so leave room for a bad connection; a
    # script refilling the disk is what this stops. Per action, per user.
    throttle to: 30, within: 1.day, by: :user, only: :update
  end

  def update
    authorize_video!(:update)
    return finalize_resumable_upload if params[:upload_id].present?

    unless params[:video].is_a?(ActionDispatch::Http::UploadedFile)
      return render_coded_error("Upload a video", code: :invalid_upload, status: :unprocessable_entity)
    end

    if video_record.attach_video!(file: params[:video], poster: params[:poster], duration_s: params[:duration_s])
      render_video_record
    else
      render_unprocessable_entity(video_record)
    end
  end

  def destroy
    authorize_video!(:destroy)
    video_record.purge_video!
    video_record.reload
    render_video_record
  end

  private

  # IDEA-9: the video arrived in chunks (ResumableUpload). Checked (size, sha256, the container by its bytes)
  # and attached with the same validations as a one-shot upload; the part is deleted either way. A second call
  # after a lost answer finds the upload completed with this record's video and answers the same.
  def finalize_resumable_upload
    upload = policy_scope(ResumableUpload).where(purpose: upload_purpose).find_by!(token: params[:upload_id].to_s)
    return render_video_record if upload.completed? && video_record.video.attached? && video_record.video.blob.id == upload.blob_id

    file, error = upload.finished_file
    # A wrong checksum or a file that is not a video cannot be resumed: the part and the upload go.
    upload.destroy if %i[upload_checksum_mismatch upload_not_a_video].include?(error)
    return render_coded_error("The upload is not finished", code: error, status: :unprocessable_entity) if error

    attached = video_record.attach_video!(file: file, poster: params[:poster], duration_s: params[:duration_s])
    file.tempfile.close
    upload.finish!(attached ? video_record.video.blob : nil)
    attached ? render_video_record : render_unprocessable_entity(video_record)
  end
end
