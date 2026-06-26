class Conversation < ApplicationRecord
  belongs_to :listing, optional: true
  belongs_to :buyer,  class_name: User.name, foreign_key: :buyer_id
  belongs_to :seller, class_name: User.name, foreign_key: :seller_id
  has_many :messages, dependent: :destroy
  # Single-row association used by the index eager-load to fetch only the
  # most-recent message per conversation — avoids pulling every message into
  # memory (the old includes(:messages) approach) while still eliminating N+1.
  has_one :latest_message, -> { order(created_at: :desc) }, class_name: Message.name

  enum :status, { open: 0, closed: 1 }

  validates :listing_id, uniqueness: { scope: :buyer_id, message: "already has a conversation with this buyer", allow_nil: true }
  validate :buyer_is_not_seller

  scope :ordered, -> { order(last_message_at: :desc, created_at: :desc) }
  scope :for_user, ->(user_id) {
    where("buyer_id = ? OR seller_id = ?", user_id, user_id)
  }

  # Scopes that filter by archive state for a specific user.
  # The caller's role (buyer vs seller) determines which column to test.
  scope :not_archived_for, ->(user) {
    where(
      "(buyer_id = ? AND buyer_archived_at IS NULL) OR (seller_id = ? AND seller_archived_at IS NULL)",
      user.id, user.id
    )
  }
  scope :archived_for, ->(user) {
    where(
      "(buyer_id = ? AND buyer_archived_at IS NOT NULL) OR (seller_id = ? AND seller_archived_at IS NOT NULL)",
      user.id, user.id
    )
  }

  # Scopes that filter by soft-delete state for a specific user.
  scope :not_deleted_for, ->(user) {
    where(
      "(buyer_id = ? AND buyer_deleted_at IS NULL) OR (seller_id = ? AND seller_deleted_at IS NULL)",
      user.id, user.id
    )
  }

  # Returns true when this conversation has been soft-deleted by the given user.
  def deleted_for?(user)
    deleted_at_for(user).present?
  end

  # Soft-deletes this conversation for the given user.
  # When both participants have soft-deleted, the record and all messages are
  # hard-deleted so orphaned data doesn't accumulate.
  def delete_for!(user)
    if buyer_id == user.id
      update_column(:buyer_deleted_at, Time.current) if buyer_deleted_at.nil?
    elsif seller_id == user.id
      update_column(:seller_deleted_at, Time.current) if seller_deleted_at.nil?
    end

    reload
    destroy! if buyer_deleted_at.present? && seller_deleted_at.present?
  end

  # Returns true when the associated listing has been removed (admin-removed or
  # hard-deleted and nullified).
  def listing_deleted?
    listing.nil? || listing.removed?
  end

  def participant?(user)
    buyer_id == user.id || seller_id == user.id
  end

  # Returns true when this conversation is archived for the given user.
  def archived_for?(user)
    archived_at_for(user).present?
  end

  # Returns the archive timestamp for the given user (nil if not archived).
  def archived_at_for(user)
    if buyer_id == user.id
      buyer_archived_at
    elsif seller_id == user.id
      seller_archived_at
    end
  end

  # Sets the caller's archive column to now (idempotent).
  def archive_for!(user)
    if buyer_id == user.id
      update_column(:buyer_archived_at, Time.current) if buyer_archived_at.nil?
    elsif seller_id == user.id
      update_column(:seller_archived_at, Time.current) if seller_archived_at.nil?
    end
  end

  # Clears the caller's archive column (idempotent).
  def unarchive_for!(user)
    if buyer_id == user.id
      update_column(:buyer_archived_at, nil) if buyer_archived_at.present?
    elsif seller_id == user.id
      update_column(:seller_archived_at, nil) if seller_archived_at.present?
    end
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

  def deleted_at_for(user)
    if buyer_id == user.id
      buyer_deleted_at
    elsif seller_id == user.id
      seller_deleted_at
    end
  end

  def latest_message_loaded?
    association(:latest_message).loaded?
  end

  def buyer_is_not_seller
    errors.add(:base, "buyer and seller must be different users") if buyer_id == seller_id
  end
end
