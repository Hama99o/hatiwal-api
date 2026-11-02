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
end
