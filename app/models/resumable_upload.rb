# IDEA-9 (1.2.1, hatiwal-mobile docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §4–4.1): a video sent in chunks,
# so a lost answer costs one chunk, not the whole clip.
#
# The bytes are appended to DIR/<token>.part — the persistent storage volume (it survives deploys), outside the
# web root, and a name the SERVER made (never the client's input: no path traversal). The client resumes from
# `offset` after a kill (HEAD); `key` (the client's UUID) makes a retried create find the same upload.
#
# Limits (§4.1): `size` ≤ HasVideo::MAX_VIDEO_SIZE and every chunk stays within it; at most MAX_OPEN open
# uploads per user; all open parts together ≤ DISK_CAP (507 beyond). Swept after STALE_AFTER without a chunk.
class ResumableUpload < ApplicationRecord
  DIR = Rails.root.join("storage/uploads")
  MAX_OPEN = 2
  # Every open upload's declared size, together.
  DISK_CAP = 2.gigabytes
  # One request's chunk: the app sends 256 KB – 4 MB.
  MAX_CHUNK = 8.megabytes
  STALE_AFTER = 24.hours
  SHA256 = /\A\h{64}\z/

  class OffsetMismatch < StandardError; end
  class TooLarge < StandardError; end

  belongs_to :user, class_name: User.name

  enum :purpose, { listing_video: 0, shop_video: 1 }, validate: true
  enum :status, { open: 0, completed: 1 }

  validates :key, presence: true, length: { maximum: 64 }
  validates :size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: HasVideo::MAX_VIDEO_SIZE }
  validates :sha256, format: { with: SHA256 }

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }
  before_validation { self.sha256 = sha256.to_s.downcase }

  scope :stale, -> { where(updated_at: ...STALE_AFTER.ago) }

  after_destroy_commit :delete_part

  def self.open_bytes = open.sum(:size)

  def part_path = DIR.join("#{token}.part")

  def complete_file? = offset == size

  # Appends `bytes` at `at` (the client's Upload-Offset). Under the row lock: a second request for the same
  # upload waits, then sees the new offset (409). Returns the new offset.
  def append!(at, bytes)
    with_lock do
      raise OffsetMismatch unless open? && at == offset
      raise TooLarge if offset + bytes.bytesize > size

      FileUtils.mkdir_p(DIR)
      File.open(part_path, "ab") do |file|
        file.truncate(offset) if file.size != offset # a half-written chunk from a crash
        file.write(bytes)
      end
      update!(offset: offset + bytes.bytesize)
      offset
    end
  end

  # The part as an uploaded file for HasVideo#attach_video!, once it is whole and is what was declared.
  # Returns [file, nil] or [nil, error_code].
  def finished_file
    return [ nil, :upload_incomplete ] unless complete_file? && File.size?(part_path) == size
    return [ nil, :upload_checksum_mismatch ] unless Digest::SHA256.file(part_path).hexdigest == sha256

    io = File.open(part_path, "rb")
    # The container by its BYTES alone: Active Storage's own identify falls back to the file name, and a
    # "video.mp4" that is a text file would pass as video/mp4.
    type = Marcel::MimeType.for(io)
    io.rewind
    unless HasVideo::VIDEO_TYPES.include?(type)
      io.close
      return [ nil, :upload_not_a_video ]
    end

    [ ActionDispatch::Http::UploadedFile.new(tempfile: io, filename: type == "video/quicktime" ? "video.mov" : "video.mp4", type: type), nil ]
  end

  def finish!(blob)
    delete_part
    update!(status: :completed, blob_id: blob&.id)
  end

  def delete_part
    FileUtils.rm_f(part_path)
  end
end
