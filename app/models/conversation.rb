class Conversation < ApplicationRecord
  belongs_to :listing
  belongs_to :buyer,  class_name: User.name, foreign_key: :buyer_id
  belongs_to :seller, class_name: User.name, foreign_key: :seller_id
  has_many :messages, dependent: :destroy
  # Single-row association used by the index eager-load to fetch only the
  # most-recent message per conversation — avoids pulling every message into
  # memory (the old includes(:messages) approach) while still eliminating N+1.
  has_one :latest_message, -> { order(created_at: :desc) }, class_name: Message.name

  enum :status, { open: 0, closed: 1 }

  validates :listing_id, uniqueness: { scope: :buyer_id, message: "already has a conversation with this buyer" }
  validate :buyer_is_not_seller

  scope :ordered, -> { order(last_message_at: :desc, created_at: :desc) }
  scope :for_user, ->(user_id) {
    where("buyer_id = ? OR seller_id = ?", user_id, user_id)
  }

  def participant?(user)
    buyer_id == user.id || seller_id == user.id
  end

  def other_participant(user)
    buyer_id == user.id ? seller : buyer
  end

  # The newest message — used by the list serializer for the preview row.
  #
  # Resolution order (fastest path first):
  #   1. latest_message already loaded via includes(:latest_message) — zero SQL.
  #   2. messages already loaded via includes(:messages) — in-memory max,
  #      no SQL (uses max_by so Rails ORDER BY is never issued on the loaded
  #      collection, which would silently bypass the preload cache).
  #   3. Fallback: fire a single ORDER BY … LIMIT 1 query.
  def last_message
    return @last_message if defined?(@last_message)

    @last_message = if latest_message_loaded?
      latest_message
    elsif messages.loaded?
      messages.max_by(&:created_at)
    else
      messages.order(created_at: :desc).first
    end
  end

  # Returns the count of unread messages not authored by +user+.
  # Falls back to a SQL COUNT when the association is not loaded (e.g. single-
  # record show action).  On the index, callers should pass a precomputed
  # hash via opts[:unread_counts] to avoid one COUNT query per row.
  def unread_count_for(user)
    if messages.loaded?
      messages.count { |m| m.read_at.nil? && m.user_id != user.id }
    else
      messages.where(read_at: nil).where.not(user_id: user.id).count
    end
  end

  private

  def latest_message_loaded?
    association(:latest_message).loaded?
  end

  def buyer_is_not_seller
    errors.add(:base, "buyer and seller must be different users") if buyer_id == seller_id
  end
end
