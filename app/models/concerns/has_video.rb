# VID (docs/LISTING_VIDEO.md) — one optional, phone-compressed video and its
# poster frame, shared by Listing and (SHOP-MEDIA, docs/SHOP_MEDIA.md) Shop.
# Everything a record needs to hold a video lives here once:
#
#   - the attachments and their validation (sniffed type, 25 MB, poster 5 MB);
#   - attach_video! — replace atomically, refuse > 60 s, leave no blob behind;
#   - the URLs the serializers read, and purge_video!.
#
# The phone compresses to ~720p / 2 Mbit/s before upload (a 30 s clip is ~5–8
# MB); 25 MB is only the server's safety net. The poster is a frame the client
# grabs, so the server needs no ffmpeg. WHEN a video is purged is each model's
# own rule (Listing.video_purgeable, Shop.media_purgeable), always after
# VIDEO_KEPT_FOR.
module HasVideo
  extend ActiveSupport::Concern

  VIDEO_TYPES           = %w[video/mp4 video/quicktime].freeze
  MAX_VIDEO_SIZE        = 25.megabytes
  MAX_VIDEO_POSTER_SIZE = 5.megabytes
  MAX_VIDEO_DURATION_S  = 60
  # A record that went away keeps its video this long (an undo, renew, restore
  # or reopen inside the window keeps it), then the purge job deletes it.
  VIDEO_KEPT_FOR = 30.days

  included do
    has_one_attached :video
    has_one_attached :video_poster
    validates :video, attached_file: { types: VIDEO_TYPES, max_size: MAX_VIDEO_SIZE }
    validates :video_poster, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: MAX_VIDEO_POSTER_SIZE }
  end

  # The blob route: it redirects to the Disk service, which answers HTTP Range,
  # so players stream the progressive MP4 (no HLS in v1).
  def video_url = video.attached? ? PublicImageUrl.original(video) : nil
  def video_poster_url = video_poster.attached? ? PublicImageUrl.variant(video_poster, :medium) : nil
  def has_video? = video.attached?

  # The length the client measured (stored on the blob at upload). Active
  # Storage's own analyzer overwrites it with ffprobe's when that is installed.
  def video_duration_s
    duration = video.attached? ? video.blob.metadata["duration"] : nil
    duration.present? ? duration.to_f.round : nil
  end

  # Replaces any previous video and poster: has_one_attached purges the old
  # blobs once the save commits. `duration_s` is the client's measurement; a clip
  # over MAX_VIDEO_DURATION_S is refused (the apps trim to 60 s before upload, so
  # only a hand-made request gets here). Returns false with errors on the
  # record, and then nothing has changed.
  def attach_video!(file:, poster: nil, duration_s: nil)
    duration = duration_s.presence&.to_f
    if duration && (duration <= 0 || duration > MAX_VIDEO_DURATION_S + 1)
      errors.add(:video, :video_too_long, count: MAX_VIDEO_DURATION_S)
      return false
    end

    video_blob = ActiveStorage::Blob.create_and_upload!(
      io: file, filename: file.original_filename.presence || "video.mp4",
      content_type: file.content_type, metadata: duration ? { "duration" => duration } : {}
    )
    self.video = video_blob
    self.video_poster = poster.presence
    if save
      warm_video_poster
      return true
    end

    video_blob.purge_later
    failed = errors.dup
    reload # drop the pending attachments
    errors.merge!(failed)
    false
  end

  # Make the poster's medium variant now, at upload, so the first viewer gets it
  # at once instead of waiting for it to be generated. Best effort.
  def warm_video_poster
    return unless video_poster.attached? && video_poster.blob.variable?

    video_poster.blob.analyze unless video_poster.blob.analyzed?
    video_poster.variant(resize_to_limit: PublicImageUrl.box(video_poster.blob, :medium), format: :webp, saver: PublicImageUrl::SAVER).processed
  rescue StandardError => e
    Rails.logger.warn("[VID] poster variant not pre-generated for #{self.class.name} #{id}: #{e.class}")
  end

  def purge_video!
    video.purge_later if video.attached?
    video_poster.purge_later if video_poster.attached?
  end
end
