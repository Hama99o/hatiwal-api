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

  # `listing`: buyer ⇄ seller about a listing (every conversation before
  # support messaging). `support`: a user (as buyer) ⇄ the Support account (as
  # seller), with no listing. Prefixed because `listing?`/`Conversation.listing`
  # would collide with the association's name.
  # Declared explicitly so the model still loads if the column is missing
  # (code booted ahead of its migration: a half-failed migrate, a rollback, a
  # console/job container that skips bin/docker-entrypoint's db:prepare).
  # Without it, `enum` raises at class load, and because ListingSerializer
  # counts conversations, that 500s the listing screen for every user — not
  # just chat. With it, everything reads as "listing"; only queries that name
  # the column (the inbox pin, support endpoints) can still fail.
  attribute :kind, :integer, default: 0
  enum :kind, { listing: 0, support: 1 }, prefix: true

  # Support threads accept plain messages only; offers, meetups and the other
  # deal kinds belong to a listing.
  SUPPORT_MESSAGE_KINDS = %w[text image_message document].freeze

  # Pins the support thread above every listing thread in the inbox.
  #
  # ORDER BY the plain `kind` COLUMN, not a CASE expression: inbox search
  # (`matching`) is SELECT DISTINCT, and Postgres rejects an ORDER BY
  # expression that is not in the select list — a CASE here made every
  # `?search=` a 500, for every user and every app version. The column is in
  # `conversations.*`, so DISTINCT accepts it. Caught by
  # spec/requests/api/v1/api_contract_v1_0_4_spec.rb.
  #
  # DESC works because support is the highest kind value; the model spec pins
  # that, so adding a kind above it fails loudly instead of reordering inboxes.
  scope :support_first, -> { order(kind: :desc) }

  # Support threads whose latest word is the user's: they have a message from
  # the user (always the buyer on a support thread) that Support hasn't read.
  # Counted per THREAD, so one chatty user can't swamp the admin badge.
  scope :awaiting_support_reply, lambda {
    kind_support.where(Message.where(read_at: nil)
                              .where("messages.conversation_id = conversations.id")
                              .where("messages.user_id = conversations.buyer_id")
                              .arel.exists)
  }

  validates :listing_id, uniqueness: { scope: :buyer_id, message: "already has a conversation with this buyer", allow_nil: true }
  validate :buyer_is_not_seller
  validate :support_thread_shape, if: :kind_support?

  # NULLS LAST matters. A conversation is created the moment a buyer opens a
  # thread from a listing, before any message is sent, so `last_message_at` is
  # legitimately NULL for a while — and Postgres sorts NULLs FIRST in a DESC
  # order. An empty thread therefore floated to the TOP of the inbox, above
  # conversations with real recent activity, pushing live negotiations down.
  # Seen in QA: an empty conversation ranked above one whose last message was
  # minutes old.
  #
  # An empty conversation also cannot be marked read or unread (there is no
  # message to mark), so having it first broke every flow that acts on "the
  # topmost row" — see UI-027.
  # Arel's `.nulls_last`, not `Arel.sql("… DESC NULLS LAST")`: a raw-SQL order
  # cannot be reversed, so `.last` on this scope raises
  # ActiveRecord::IrreversibleOrderError. No caller does that today, but leaving
  # a scope that explodes on `.last` is a trap for the next one.
  scope :ordered, lambda {
    order(arel_table[:last_message_at].desc.nulls_last, created_at: :desc)
  }
  scope :for_user, ->(user_id) {
    where("buyer_id = ? OR seller_id = ?", user_id, user_id)
  }

  # Role-scoped views of the inbox (TASK-R517) — "conversations where I am
  # buying" vs "conversations where I am selling". Used by the controller's
  # `role` query param so a user with 20 buyer threads and their own selling
  # threads can triage each side separately.
  # SERVER-SIDE search across the whole inbox, not just the loaded page.
  #
  # Owner, 2026-09-02: "the message conversation search is not working, like it's
  # not connected with backend, it's not search in db". He was right: the clients
  # filtered `filterConversations` over items ALREADY in memory, so anything past
  # the first page was unfindable, and the UI even shipped a string admitting it
  # ("Showing results in loaded conversations only").
  #
  # Matches what a person would expect to search by, which is what the client
  # filter already used: the other party's name, the listing's title, and the text
  # of any message in the thread.
  #
  # LEFT joins throughout, with explicit aliases. `listing` is optional? true, and
  # a thread with no messages yet must not vanish from its own search results;
  # buyer and seller are both `users`, so Rails' generated aliases are not stable
  # enough to write a WHERE against.
  scope :matching, lambda { |term|
    q = term.to_s.strip
    next all if q.blank?

    like = "%#{sanitize_sql_like(q)}%"
    left_joins(:messages)
      .joins("LEFT JOIN listings   ON listings.id  = conversations.listing_id")
      .joins("LEFT JOIN users AS b ON b.id         = conversations.buyer_id")
      .joins("LEFT JOIN users AS s ON s.id         = conversations.seller_id")
      .where(
        "listings.title ILIKE :like
         OR b.firstname ILIKE :like OR b.lastname ILIKE :like
         OR s.firstname ILIKE :like OR s.lastname ILIKE :like
         OR messages.body ILIKE :like",
        like: like
      )
      .distinct
  }

  scope :as_buyer_for, ->(user) { where(buyer_id: user.id) }
  scope :as_seller_for, ->(user) { where(seller_id: user.id) }

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

  # The user's support thread, creating it on first call. Only ever called on
  # the user's own request (POST /support_conversation, which only the new app
  # has) or by an admin when SUPPORT_ADMIN_INITIATE is on — see
  # docs/SUPPORT_MESSAGING.md for why that distinction is the safety.
  def self.support_thread_for!(user)
    existing = kind_support.find_by(buyer_id: user.id)
    # Asking for support again brings a thread the user archived or deleted
    # back into their inbox. Otherwise "Contact support" would return a thread
    # their inbox hides.
    return existing.tap(&:resurface_support_thread!) if existing

    create!(kind: :support, buyer: user, seller: User.support_account!)
  rescue ActiveRecord::RecordNotUnique
    kind_support.find_by!(buyer_id: user.id)
  end

  # ── The admin-side gate (docs/SUPPORT_MESSAGING.md) ─────────────────────
  #
  # May an admin put a message in front of this user in the app? Only if the
  # user ALREADY has a support thread — only the app version with support
  # messaging can open one, so they are on it — or SUPPORT_ADMIN_INITIATE is on
  # (most users have updated). Otherwise a v1.0.4 user would get it as a
  # "removed listing" chat. The ONE place this is decided; views only reflect it.
  def self.admin_initiate_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("SUPPORT_ADMIN_INITIATE", "false"))
  end

  def self.admin_can_message?(user)
    admin_message_refusal(user).nil?
  end

  def self.admin_message_refusal(user)
    return "the Support account" if user.support_account?
    return "the account is deleted" if user.deleted_at.present?
    return nil if kind_support.exists?(buyer_id: user.id) || admin_initiate_enabled?

    "needs the app update with support messaging (SUPPORT_ADMIN_INITIATE)"
  end

  # The ONLY way admin code may obtain a support thread: the existing one, or a
  # new one when the gate allows; nil otherwise. Admin code must never call
  # support_thread_for! (user-initiated, ungated) — a spec enforces that.
  def self.admin_support_thread_for(user)
    return nil unless admin_can_message?(user)

    kind_support.find_by(buyer_id: user.id) ||
      create!(kind: :support, buyer: user, seller: User.support_account!)
  rescue ActiveRecord::RecordNotUnique
    kind_support.find_by(buyer_id: user.id)
  end

  # A support thread the user archived or deleted comes back when anything new
  # happens in it, from either side. Archive and delete are per side, so this
  # never affected the admin, who reads every support thread regardless.
  #
  # It deliberately does NOT touch read state: a thread that returns already
  # marked read is one the user never opens. The new message stays unread.
  #
  # SUPPORT ONLY. Listing threads keep today's behaviour (an archived thread
  # stays archived when the other side replies). Changing that for everyone is
  # a separate decision — see docs/SUPPORT_MESSAGING.md, "Archived threads".
  def resurface_support_thread!
    return unless kind_support?

    # Straight to the database, not "if self[column].present?": the instance
    # in hand is often stale (loaded before the user archived), and trusting
    # it left an archived thread hidden. One UPDATE per support message.
    shown = { buyer_archived_at: nil, buyer_deleted_at: nil, seller_archived_at: nil, seller_deleted_at: nil }
    self.class.where(id: id).update_all(shown)
    shown.each_key { |column| self[column] = nil }
    clear_attribute_changes(shown.keys)
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

  def support_thread_shape
    errors.add(:listing_id, "must be empty on a support thread") if listing_id.present?
    errors.add(:seller_id, "must be the Support account on a support thread") unless seller&.support_account?
    errors.add(:buyer_id, "cannot be the Support account") if buyer&.support_account?
  end
end
