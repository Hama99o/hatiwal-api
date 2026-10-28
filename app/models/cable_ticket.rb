# Privacy review 2026-10-28 — a single-use pass for the chat's live connection
# (the cable). A browser cannot set WebSocket headers, so hatiwal-web had to put
# the whole session (access-token, client, uid = the email) in the connect URL,
# where proxy access logs may keep it. It now puts a ticket there instead:
# random, worth ONE connect, for TTL. Only its SHA-256 digest is stored.
class CableTicket < ApplicationRecord
  TTL = 60.seconds
  MAX_LENGTH = 128

  belongs_to :user, class_name: User.name

  validates :digest, presence: true, length: { is: 64 }
  validates :expires_at, presence: true

  scope :expired, -> { where(expires_at: ..Time.current) }

  # The ticket to hand out (never stored as such).
  def self.issue!(user)
    ticket = SecureRandom.urlsafe_base64(32)
    create!(user: user, digest: digest_of(ticket), expires_at: TTL.from_now)
    ticket
  end

  # Its user, once: the row is locked and removed in one transaction, so two
  # connects with the same ticket cannot both get it. An expired ticket is
  # removed too, and gives nothing.
  def self.consume(ticket)
    return nil unless ticket.is_a?(String) && ticket.present? && ticket.length <= MAX_LENGTH

    transaction do
      row = lock.find_by(digest: digest_of(ticket))
      next nil unless row

      row.destroy!
      row.expires_at.future? ? row.user : nil
    end
  end

  def self.digest_of(ticket) = Digest::SHA256.hexdigest(ticket)
end
