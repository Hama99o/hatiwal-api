# A PERMANENT URL for a PUBLIC image (listing photos, avatars, shop logos and
# covers): the blob redirect route, keyed by the blob's signed_id, never
# changes — so the apps' URL-keyed image caches hit (owner, 2026-10-09: My
# listings re-downloaded every photo on each visit).
#
# Never use it for a PRIVATE file: anyone holding a permanent link can open the
# file forever. Message attachments keep `attachment.url` (signed, expiring);
# verification files are refused by the public routes altogether
# (config/initializers/private_verification_files.rb).
# spec/edge/stable_image_urls_spec.rb guards both.
module PublicImageUrl
  # Light variants (owner, 2026-10-09: "Cloudinary without paying for it").
  # Lists show THUMB, the gallery MEDIUM, zoom the original. Sized for the real
  # display at 3x density (owner: "the images must show well").
  #   thumb / avatar: cards and avatars COVER-crop, so what must be sharp is the
  #     SHORT side: a 2-column card is ~180 dp → 540 px, hence 640 (avatars
  #     ≤ 80 dp → 256), the long side capped at 2.5x.
  #   medium: the gallery CONTAINS the photo in ~400 dp width → the long side
  #     ≤ 1440.
  # resize_to_limit never upscales and never crops (a 300 px original stays
  # 300 px). WebP: the production image's libvips (Debian 13, 8.16) has it.
  SIZES = { thumb: [ 640, 1600 ], avatar: [ 256, 512 ], medium: [ 1440, 1440 ] }.freeze
  SAVER = { quality: 80, strip: true }.freeze
  # What `for` serves: the photo at full size (zoom), its own format (PNG keeps
  # its alpha), WITHOUT its metadata. A phone JPEG carries EXIF with GPS, and the
  # web uploads the raw file: serving the original published the seller's home
  # coordinates (d0 hunt round 2, 2026-10-11).
  FULL_LIMIT = [ 4096, 4096 ].freeze
  FULL_SAVER = { quality: 90, strip: true }.freeze

  module_function

  # A LAZY representation URL (generated on the first request, then stored),
  # stable like the blob route; building it runs no query. Falls back to the
  # original when a variant could fail: not variable (a PDF…), or no analysed
  # width (a corrupt file vips cannot read, or not analysed yet) — the client
  # then shows exactly what it shows today, never a 500.
  def variant(attachment, size)
    return nil unless attachment.respond_to?(:attached?) ? attachment.attached? : attachment.present?
    return original(attachment) unless processable?(attachment.blob)

    Rails.application.routes.url_helpers.rails_representation_url(
      attachment.variant(resize_to_limit: box(attachment.blob, size), format: :webp, saver: SAVER),
      **(ActiveStorage::Current.url_options || {})
    )
  rescue StandardError
    nil
  end

  # The public URL of an image: a stripped full-size variant (FULL_SAVER) —
  # stable like the blob route and lazily generated. A blob that can't be
  # processed (not variable, or no analysed width) falls back to the original,
  # as before. nil when nothing is attached (or the URL cannot be built).
  def for(attachment)
    return nil unless attachment.respond_to?(:attached?) ? attachment.attached? : attachment.present?
    return original(attachment) unless processable?(attachment.blob)

    Rails.application.routes.url_helpers.rails_representation_url(
      attachment.variant(resize_to_limit: FULL_LIMIT, saver: FULL_SAVER),
      **(ActiveStorage::Current.url_options || {})
    )
  rescue StandardError
    nil
  end

  # The stored file itself, permanent (blob redirect route). Only for a blob
  # that can't be processed: an original may carry EXIF/GPS.
  def original(attachment)
    Rails.application.routes.url_helpers.rails_blob_url(attachment, **(ActiveStorage::Current.url_options || {}))
  rescue StandardError
    nil
  end

  # [width, height] limits. thumb/avatar: the short side gets the first number,
  # by the analysed orientation (ActiveStorage swaps width/height for EXIF
  # rotations, and vips autorotates).
  def box(blob, size)
    short, long = SIZES.fetch(size)
    return [ short, long ] if size == :medium

    blob.metadata["width"].to_i >= blob.metadata["height"].to_i ? [ long, short ] : [ short, long ]
  end

  def processable?(blob)
    blob.variable? && blob.metadata["width"].to_i.positive?
  end
end
