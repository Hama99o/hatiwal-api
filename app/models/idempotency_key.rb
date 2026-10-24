# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1) — a write the phone may send
# more than once. The outbox gives every queued write a UUID; when the answer
# to a request is lost (the phone never got it), the retry carries the same key
# and gets the FIRST answer back instead of doing the write twice.
#
# Rows live KEPT_FOR (30 days): longer than the outbox keeps a frozen item.
class IdempotencyKey < ApplicationRecord
  KEPT_FOR = 30.days
  HEADER = "Idempotency-Key".freeze
  FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/

  belongs_to :user, class_name: User.name

  enum :status, { in_progress: 0, completed: 1 }

  validates :key, presence: true, format: { with: FORMAT }
  validates :request_fingerprint, presence: true, length: { is: 64 }

  scope :expired, -> { where(created_at: ...KEPT_FOR.ago) }

  def self.valid_key?(key)
    key.is_a?(String) && FORMAT.match?(key)
  end
end
