# Validates Active Storage attachments: the file TYPE, the file SIZE, and how
# MANY files one attachment may hold.
#
# Nothing validated attachments before this. `listing[images][]`, `user[avatar]`
# and a message `attachment` were all permitted straight through to
# `Attached#attach`, so any HTTP client could store a 500 MB non-image — the
# only ceiling was the photo picker in each client, which curl does not use.
#
# Works with both has_one_attached and has_many_attached:
#
#   validates :avatar, attached_file: { types:    AttachedFileValidator::IMAGE_TYPES,
#                                       max_size: 5.megabytes }
#   validates :images, attached_file: { types:     AttachedFileValidator::IMAGE_TYPES,
#                                       max_size:  10.megabytes,
#                                       max_count: 8 }
#
# The content type checked is the one on the BLOB, which Active Storage derives
# with Marcel from the file's own leading bytes (declared_type is only a hint).
# A .exe renamed photo.jpg and uploaded as `image/jpeg` is therefore still
# rejected — this is not a filename check.
class AttachedFileValidator < ActiveModel::EachValidator
  # Everything a phone camera or a desktop file picker realistically produces.
  # HEIC/HEIF matter specifically: the mobile uploader converts to JPEG first
  # but falls back to the ORIGINAL file when conversion fails
  # (appendImageUri in hatiwal-mobile/src/api/listings.ts), and that original
  # is HEIC on iOS.
  IMAGE_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/gif
    image/heic
    image/heif
    image/avif
  ].freeze

  # Chat attachments may also be documents — the web picker accepts
  # .pdf/.doc/.docx/.txt (conversation-thread.tsx) and mobile passes the
  # document picker's own mime type straight through.
  DOCUMENT_TYPES = %w[
    application/pdf
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  ].freeze

  def check_validity!
    return if options[:types].present? || options[:max_size].present? || options[:max_count].present?

    raise ArgumentError, "attached_file needs at least one of :types, :max_size, :max_count"
  end

  def validate_each(record, attribute, value)
    blobs = blobs_for(value)
    return if blobs.empty?

    validate_count(record, attribute, blobs)
    blobs.each do |blob|
      validate_type(record, attribute, blob)
      validate_size(record, attribute, blob)
    end
  end

  private

  # has_many_attached exposes `blobs` (pending changes included); has_one_attached
  # exposes a single `blob` and only responds to it once something is attached —
  # so an empty attachment falls through to [] and validates as a no-op.
  def blobs_for(value)
    if value.respond_to?(:blobs)
      Array(value.blobs)
    elsif value.respond_to?(:blob)
      Array(value.blob)
    else
      []
    end
  end

  def validate_count(record, attribute, blobs)
    max = options[:max_count]
    return if max.blank? || blobs.size <= max

    record.errors.add(attribute, :too_many_files, count: max)
  end

  def validate_type(record, attribute, blob)
    types = options[:types]
    return if types.blank? || types.include?(blob.content_type)

    record.errors.add(attribute, :invalid_file_type, content_type: blob.content_type.presence || "unknown")
  end

  def validate_size(record, attribute, blob)
    max = options[:max_size]
    return if max.blank? || blob.byte_size.to_i <= max

    record.errors.add(attribute, :file_too_large, limit: ActiveSupport::NumberHelper.number_to_human_size(max))
  end
end
