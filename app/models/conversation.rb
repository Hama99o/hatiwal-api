class Conversation < ApplicationRecord
  belongs_to :listing, optional: true
  # SHOP-2 — a "Message shop" chat from the shop page: no listing, the shop
  # instead (one per buyer and shop). A chat about a shop's PRODUCT keeps
  # shop_id nil: it belongs to the shop through its listing.
  belongs_to :shop, optional: true
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
  # SHOP-1 — the Chat tab follows who you sell as: a shop's chats are the ones
  # whose listing belongs to the shop; personal chats are the rest (including
  # support threads, which have no listing).
  # SHOP-2: plus the shop's listing-less chats.
  # The chat's shop is PINNED when it starts (conversations.shop_id): a chat that
  # began on a personal product stays personal even if the product later moves
  # into a shop (the buyer wrote to a person; staff never see personal chats).
  scope :for_shop, ->(shop_id) { where(shop_id: shop_id) }
  scope :without_shop, -> { where(shop_id: nil) }
  scope :support_first, -> { order(kind: :desc) }

  # Support threads whose latest word is the user's: they have a message from
  # the user (always the buyer on a support thread) that Support hasn't read.
  # Counted per THREAD, so one chatty user can't swamp the admin badge.
  # Support threads whose latest word is the user's: an unread message that
  # Support didn't write (the person on their thread, any member on a shop's).
  scope :awaiting_support_reply, lambda {
    kind_support.where(Message.where(read_at: nil)
                              .where("messages.conversation_id = conversations.id")
                              .where(NOT_FROM_SUPPORT_SQL)
                              .arel.exists)
  }

  # A message written by the person (or, on a shop's thread, a member), not by
  # the Hatiwal Support account.
  NOT_FROM_SUPPORT_SQL = "messages.user_id NOT IN (SELECT id FROM users WHERE users.support_account)".freeze

  # Owner, 2026-10-12: Support is SEPARATED per identity. A person's own thread
  # (no shop: Buyer mode and Seller as Me) and one thread PER SHOP, shown only
  # when that shop is selected. A shop's thread has the Support account on the
  # BUYER side and the shop's owner on the seller side, so the team shares it
  # like the shop's chats (SELLER_SIDE_SQL), and a transfer moves it with them.
  scope :person_support, -> { kind_support.where(shop_id: nil) }
  scope :shop_support, -> { kind_support.where.not(shop_id: nil) }

  # One chat per listing, buyer AND selling identity (shop_id; nil = the person):
  # a listing moved to another shop starts a new chat there, the old one stays
  # with the identity it began with (Listings::MoveService).
  # A personal chat is also pinned to its seller: a listing that left Me and came
  # back with another poster starts a new chat (edge pass 2026-10-08).
  validates :listing_id, uniqueness: { scope: %i[buyer_id shop_id], message: "already has a conversation with this buyer", allow_nil: true },
                         if: -> { shop_id.present? }
  validates :listing_id, uniqueness: { scope: %i[buyer_id seller_id], conditions: -> { where(shop_id: nil) },
                                       message: "already has a conversation with this buyer", allow_nil: true },
                         if: -> { shop_id.nil? }
  validate :buyer_is_not_seller
  validate :support_thread_shape, if: :kind_support?
  validate :shop_chat_shape, if: :shop_chat?

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
  # SHOP-3 — "the seller side" of a chat: its seller, or any member of the
  # chat's shop (its own shop for a Message-shop chat, else its listing's).
  # Personal chats have no shop, so a team member never reaches one.
  SELLER_SIDE_SQL = <<~SQL.squish.freeze
    (conversations.seller_id = :u OR EXISTS (
      SELECT 1 FROM shop_members sm
       WHERE sm.user_id = :u
         AND sm.shop_id = conversations.shop_id))
  SQL

  # Messages `:u` hasn't read that count as inbound: not their own, and, on
  # the seller side of a shop chat, only the buyer's (the team shares one
  # inbox). Decided by the AUTHOR, not by today's team: a former member's
  # messages stay the shop's, never "unread" for the rest (edge pass 2026-10-08).
  INBOUND_MESSAGE_SQL = <<~SQL.squish.freeze
    messages.user_id <> :u AND (conversations.buyer_id = :u OR messages.user_id = conversations.buyer_id)
  SQL

  # A user with no shop (almost everyone) gets the plain, shop-free SQL: the
  # team subqueries run only for members (users.shop_memberships_count, a
  # counter column, so deciding costs nothing).
  def self.seller_side_sql_for(user)
    team_member?(user) ? SELLER_SIDE_SQL : "conversations.seller_id = :u"
  end

  def self.inbound_message_sql_for(user)
    team_member?(user) ? INBOUND_MESSAGE_SQL : "messages.user_id <> :u"
  end

  # A bare id can't tell, so it gets the team-aware SQL (always correct).
  def self.team_member?(user) = !user.is_a?(User) || user.shop_memberships_count.to_i.positive?

  scope :for_user, ->(user) {
    where("conversations.buyer_id = :u OR #{seller_side_sql_for(user)}", u: user.is_a?(User) ? user.id : user)
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
      .joins("LEFT JOIN shops AS sh ON sh.id       = conversations.shop_id")
      .where(
        # SHOP-2: a chat with a shop is found by the shop's name, never by the
        # owner's personal one (that would tell the buyer who is behind it).
        "listings.title ILIKE :like
         OR b.firstname ILIKE :like OR b.lastname ILIKE :like
         OR ((s.firstname ILIKE :like OR s.lastname ILIKE :like) AND sh.id IS NULL)
         OR sh.name ILIKE :like
         OR messages.body ILIKE :like",
        like: like
      )
      .distinct
  }

  scope :as_buyer_for, ->(user) { where(buyer_id: user.id) }
  scope :as_seller_for, ->(user) { where(seller_side_sql_for(user), u: user.id) }

  # Scopes that filter by archive state for a specific user.
  # The caller's role (buyer vs seller) determines which column to test.
  # The seller side's columns are shared by the shop's team (SHOP-3).
  scope :not_archived_for, ->(user) {
    where(
      "(conversations.buyer_id = :u AND conversations.buyer_archived_at IS NULL) OR " \
      "(#{seller_side_sql_for(user)} AND conversations.seller_archived_at IS NULL)", u: user.id
    )
  }
  scope :archived_for, ->(user) {
    where(
      "(conversations.buyer_id = :u AND conversations.buyer_archived_at IS NOT NULL) OR " \
      "(#{seller_side_sql_for(user)} AND conversations.seller_archived_at IS NOT NULL)", u: user.id
    )
  }

  # Scopes that filter by soft-delete state for a specific user.
  scope :not_deleted_for, ->(user) {
    where(
      "(conversations.buyer_id = :u AND conversations.buyer_deleted_at IS NULL) OR " \
      "(#{seller_side_sql_for(user)} AND conversations.seller_deleted_at IS NULL)", u: user.id
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
    case side_for(user)
    when :buyer
      update_column(:buyer_deleted_at, Time.current) if buyer_deleted_at.nil?
    when :seller
      update_column(:seller_deleted_at, Time.current) if seller_deleted_at.nil?
    end

    reload
    destroy! if buyer_deleted_at.present? && seller_deleted_at.present?
  end

  # Returns true when the associated listing has been removed (admin-removed or
  # hard-deleted and nullified).
  # TRUE whenever there is no listing, a "Message shop" chat included: clients
  # older than SHOP-2 read `listing_deleted: false` + `listing: null` as a live
  # listing and crash on `listing.title` (see ConversationSerializer). New
  # clients branch on `shop_chat` first, like `kind` for support threads.
  def listing_deleted?
    listing.nil? || listing.removed?
  end

  # SHOP-2 — a "Message shop" chat (no product).
  def shop_chat? = kind_listing? && shop_id.present? && listing_id.nil?

  # Support (owner, 2026-10-12): a shop's own thread, or a person's.
  def shop_support? = kind_support? && shop_id.present?
  def person_support? = kind_support? && shop_id.nil?

  # The Hatiwal Support account in this thread: the buyer on a shop's thread,
  # the seller on a person's.
  def support_user
    return nil unless kind_support?

    shop_support? ? buyer : seller
  end

  # The shop this chat is with: its own (a shop chat) or its product's.
  # The shop this chat is with: the one PINNED when it started (both a
  # Message-shop chat and a chat about a shop's product), never the product's
  # current shop.
  def chat_shop = shop

  # The shop the SELLER side speaks as, or nil. Owner, 2026-10-05: whatever is
  # done as the shop shows the shop, never the person — so the buyer gets the
  # shop's name and logo in place of the owner's. A product chat until the shop
  # is CLOSED (a closed shop's products went back to the owner); a "Message
  # shop" chat always. A suspended (or pending) shop keeps its face: suspension
  # is temporary and must not show the buyer the owner's or a member's personal
  # name (edge pass 2026-10-08).
  def shop_face
    s = chat_shop
    s if s && (shop_chat? || !s.closed?)
  end

  def participant?(user)
    side_for(user).present?
  end

  # :buyer, :seller (the seller or, SHOP-3, a member of the chat's shop) or nil.
  def side_for(user)
    return nil unless user
    return :buyer if buyer_id == user.id

    :seller if seller_side?(user)
  end

  def seller_side?(user)
    return false unless user
    return true if seller_id == user.id

    seller_side_user_ids.include?(user.id)
  end

  # The seller plus the chat's shop team (memoized: the message serializer
  # asks once per message of the same conversation).
  def seller_side_user_ids
    @seller_side_user_ids ||= begin
      shop = chat_shop
      [ seller_id, *(shop ? shop.shop_members.pluck(:user_id) : []) ].uniq
    end
  end

  # A teammate wrote it as the shop (MessageSerializer, push titles): anyone on
  # the seller side, i.e. not the buyer — by the author, not by today's team, so
  # what a member wrote stays the shop's after they leave and their personal
  # name never surfaces to the buyer (edge pass 2026-10-08).
  def written_as_shop?(user_id) = shop_face.present? && user_id.present? && user_id != buyer_id

  # SHOP-3 — why a team member (seller side, not the seller) can't send here,
  # or nil: a block between the buyer and the OWNER ends the chat for the whole
  # shop; a block between the buyer and THIS member stops only them.
  def team_block_code(user)
    return nil unless side_for(user) == :seller && seller_id != user.id && buyer

    return :blocked_by if buyer.blocked?(user) || buyer.blocked?(seller)
    return :blocked if user.blocked?(buyer) || seller.blocked?(buyer)

    nil
  end

  # What `user` hasn't read: see INBOUND_MESSAGE_SQL.
  def inbound_messages_for(user)
    scope = messages.where.not(user_id: user.id)
    side_for(user) == :seller ? scope.where(user_id: buyer_id) : scope
  end

  # Returns true when this conversation is archived for the given user.
  def archived_for?(user)
    archived_at_for(user).present?
  end

  # Returns the archive timestamp for the given user (nil if not archived).
  def archived_at_for(user)
    case side_for(user)
    when :buyer then buyer_archived_at
    when :seller then seller_archived_at
    end
  end

  # Sets the caller's archive column to now (idempotent).
  def archive_for!(user)
    case side_for(user)
    when :buyer then update_column(:buyer_archived_at, Time.current) if buyer_archived_at.nil?
    when :seller then update_column(:seller_archived_at, Time.current) if seller_archived_at.nil?
    end
  end

  # Clears the caller's archive column (idempotent).
  def unarchive_for!(user)
    case side_for(user)
    when :buyer then update_column(:buyer_archived_at, nil) if buyer_archived_at.present?
    when :seller then update_column(:seller_archived_at, nil) if seller_archived_at.present?
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
      seller = side_for(user) == :seller
      messages.count { |m| m.read_at.nil? && m.user_id != user.id && (!seller || m.user_id == buyer_id) }
    else
      inbound_messages_for(user).where(read_at: nil).count
    end
  end

  # The user's support thread, creating it on first call. Only ever called on
  # the user's own request (POST /support_conversation, which only the new app
  # has) or by an admin when SUPPORT_ADMIN_INITIATE is on — see
  # docs/SUPPORT_MESSAGING.md for why that distinction is the safety.
  def self.support_thread_for!(user)
    existing = person_support.find_by(buyer_id: user.id)
    # Asking for support again brings a thread the user archived or deleted
    # back into their inbox. Otherwise "Contact support" would return a thread
    # their inbox hides.
    return existing.tap(&:resurface_support_thread!) if existing

    create!(kind: :support, buyer: user, seller: User.support_account!)
  rescue ActiveRecord::RecordNotUnique
    person_support.find_by!(buyer_id: user.id)
  end

  # A shop's thread, created on first call: asked for by a member (POST
  # /support_conversation with shop_id), like a person's own.
  def self.shop_support_thread_for!(shop)
    existing = shop_support.find_by(shop_id: shop.id)
    return existing.tap(&:resurface_support_thread!) if existing

    create!(kind: :support, shop: shop, buyer: User.support_account!, seller: shop.owner)
  rescue ActiveRecord::RecordNotUnique
    shop_support.find_by!(shop_id: shop.id)
  end

  # ── The admin-side gate (docs/SUPPORT_MESSAGING.md) ─────────────────────
  #
  # May an admin put a message in front of this user in the app? Only if the
  # user ALREADY has a support thread — only the app version with support
  # messaging can open one, so they are on it — or SUPPORT_ADMIN_INITIATE is on
  # (most users have updated). Otherwise a v1.0.4 user would get it as a
  # "removed listing" chat. The ONE place this is decided; views only reflect it.
  # The user archived or deleted their side of this thread — for a broadcast,
  # that means "no announcements, please" (Message#update_conversation_last_message_at).
  def muted_by_buyer?
    buyer_archived_at.present? || buyer_deleted_at.present?
  end

  def self.admin_initiate_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("SUPPORT_ADMIN_INITIATE", "false"))
  end

  def self.admin_can_message?(user)
    admin_message_refusal(user).nil?
  end

  def self.admin_message_refusal(user)
    return "the Support account" if user.support_account?
    return "the account is deleted" if user.deleted_at.present?
    return nil if person_support.exists?(buyer_id: user.id) || admin_initiate_enabled?

    "needs the app update with support messaging (SUPPORT_ADMIN_INITIATE)"
  end

  # The same gate for a shop's thread. Shops exist only on apps that have
  # support messaging, so a closed shop is the one refusal beyond the switch.
  def self.admin_shop_message_refusal(shop)
    return "the shop is closed" if shop.closed?
    return nil if shop_support.exists?(shop_id: shop.id) || admin_initiate_enabled?

    "needs the app update with support messaging (SUPPORT_ADMIN_INITIATE)"
  end

  def self.admin_shop_support_thread_for(shop)
    return nil if admin_shop_message_refusal(shop)

    shop_support.find_by(shop_id: shop.id) ||
      create!(kind: :support, shop: shop, buyer: User.support_account!, seller: shop.owner)
  rescue ActiveRecord::RecordNotUnique
    shop_support.find_by(shop_id: shop.id)
  end

  # The ONLY way admin code may obtain a support thread: the existing one, or a
  # new one when the gate allows; nil otherwise. Admin code must never call
  # support_thread_for! (user-initiated, ungated) — a spec enforces that.
  def self.admin_support_thread_for(user)
    return nil unless admin_can_message?(user)

    person_support.find_by(buyer_id: user.id) ||
      create!(kind: :support, buyer: user, seller: User.support_account!)
  rescue ActiveRecord::RecordNotUnique
    person_support.find_by(buyer_id: user.id)
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
    case side_for(user)
    when :buyer then buyer_deleted_at
    when :seller then seller_deleted_at
    end
  end

  def latest_message_loaded?
    association(:latest_message).loaded?
  end

  def buyer_is_not_seller
    errors.add(:base, "buyer and seller must be different users") if buyer_id == seller_id
  end

  def shop_chat_shape
    errors.add(:listing_id, "must be empty on a shop chat") if listing_id.present?
    errors.add(:kind, "must be listing on a shop chat") unless kind_listing?
    errors.add(:seller_id, "must be the shop's owner") if new_record? && shop && seller_id != shop.owner_id
  end

  def support_thread_shape
    errors.add(:listing_id, "must be empty on a support thread") if listing_id.present?
    if shop_id.present?
      errors.add(:buyer_id, "must be the Support account on a shop's support thread") unless buyer&.support_account?
      errors.add(:seller_id, "must be the shop's owner") if new_record? && shop && seller_id != shop.owner_id
    else
      errors.add(:seller_id, "must be the Support account on a support thread") unless seller&.support_account?
      errors.add(:buyer_id, "cannot be the Support account") if buyer&.support_account?
    end
  end
end
