# A photo sent to be LOOKED AT, never kept: search by image
# (docs/IMAGE_SEARCH.md) and sell with a photo (docs/SELL_WITH_PHOTO.md).
#
# Same size cap and type list as a listing photo; the type comes from the
# file's own leading bytes (Marcel), never from its name or declared type. The
# photo is read into memory and its tempfile deleted at once: it is never
# attached, saved, logged or sent anywhere.
module LookedAtPhotoParam
  extend ActiveSupport::Concern

  LOOKED_AT_PHOTO_ERRORS = {
    image_missing:   "Add one photo.",
    image_too_large: "This photo is too large (10 MB max).",
    invalid_image:   "This file is not a photo we can read."
  }.freeze

  private

  # Returns [bytes, nil] or [nil, error code].
  def read_looked_at_photo
    upload = params[:image]
    return [ nil, :image_missing ] unless upload.respond_to?(:tempfile)
    return [ nil, :image_too_large ] if upload.size > Listing::MAX_IMAGE_SIZE

    type = Marcel::MimeType.for(upload.tempfile)
    return [ nil, :invalid_image ] unless AttachedFileValidator::IMAGE_TYPES.include?(type)

    upload.tempfile.rewind
    [ upload.tempfile.read, nil ]
  ensure
    upload.tempfile.close! if upload.respond_to?(:tempfile)
  end

  def render_looked_at_photo_error(code)
    render_unprocessable_entity(LOOKED_AT_PHOTO_ERRORS.fetch(code), code: code)
  end
end
