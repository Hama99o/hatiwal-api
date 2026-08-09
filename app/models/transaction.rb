# A completed (or in-progress) sale between a seller and a buyer for one
# listing. Created/advanced from Listing#reserve_with_buyer! and
# Listing#sold_with_buyer! when the seller identifies the buyer from the
# listing's conversations (TASK-TX01). Legacy reserve/sold calls that omit a
# buyer never touch this table.
class Transaction < ApplicationRecord
  belongs_to :listing
  belongs_to :seller, class_name: User.name
  belongs_to :buyer,  class_name: User.name

  has_many :reviews, class_name: Review.name, foreign_key: :transaction_id, dependent: :destroy, inverse_of: :sale

  enum :status, { reserved: 0, sold: 1 }

  validates :final_price, presence: true, numericality: { greater_than: 0 }
  # `in:` takes a lambda (not `Listing::CURRENCIES` directly) so this constant
  # is resolved lazily at validation time, not when this file is loaded —
  # avoids a load-order cycle with Listing (which references Transaction.name
  # in its own `has_many`, autoloading this file while Listing's class body,
  # including its CURRENCIES constant, is still being evaluated).
  validates :currency, presence: true, inclusion: { in: -> { Listing::CURRENCIES } }
  validate :buyer_is_not_seller
  validate :seller_matches_listing_owner
  validate :buyer_is_conversation_participant

  # ── Trust-stat counters (TASK-TX02) ─────────────────────────────────────────
  # Bump the denormalized users.sold_count / users.bought_count columns the
  # moment a transaction FIRST becomes sold — whether created directly as sold
  # (skip-reserve) or advanced from reserved via #mark_sold!. Fires at most
  # once per transaction (guarded by saved_change_to_status?), so correcting
  # other attributes on an already-sold row never double-counts. There is
  # currently no "unsell" flow, so counters are only ever incremented.
  #
  # Review fix (TASK-TX02, MED — "no compensating path"): this is safe ONLY
  # because a `Listing` can never re-trigger `sold` once it reaches that
  # terminal status — `ListingPolicy#sold?` requires `active?`/`reserved?`, so
  # a repeat `PUT .../sold` on an already-sold listing 403s before the bump
  # logic ever runs (see the regression spec "rejects a repeat sold call on an
  # already-sold listing" in spec/requests/api/v1/my/listings_spec.rb). If a
  # future feature ever allows re-selling, relisting, or un-selling a listing,
  # a real decrement path must be added here — don't assume increment-only
  # stays safe. Note this counter is also intentionally a LIFETIME stat: it is
  # NOT decremented when a sold listing is later soft-removed, so it can
  # legitimately read higher than the public "Sold" showcase tab (which only
  # lists currently-visible sold listings) — the mobile client accounts for
  # this explicitly (see soldShowcaseEmptyState.ts).
  after_save :bump_trust_counters!, if: -> { sold? && saved_change_to_status? }

  scope :as_buyer,  ->(user) { where(buyer_id: user.id) }
  scope :as_seller, ->(user) { where(seller_id: user.id) }
  scope :for_user,  ->(user) { where("buyer_id = ? OR seller_id = ?", user.id, user.id) }
  scope :ordered,   -> { order(created_at: :desc) }

  # Advances an existing (reserved) transaction to sold, optionally updating
  # the final price and/or buyer (a seller may correct their buyer pick right
  # up until the sale is finalized).
  def mark_sold!(final_price: nil, buyer_id: nil)
    update!(
      status: :sold,
      completed_at: Time.current,
      final_price: final_price.presence || self.final_price,
      buyer_id: buyer_id.presence || self.buyer_id
    )
  end

  private

  # Atomic single-column UPDATEs (no read-then-write race, no extra SELECT) —
  # same reasoning as ActiveRecord's own #increment_counter.
  def bump_trust_counters!
    User.increment_counter(:sold_count, seller_id)
    User.increment_counter(:bought_count, buyer_id)
  end

  def buyer_is_not_seller
    return if buyer_id.blank? || seller_id.blank?

    errors.add(:buyer_id, "must be different from the seller") if buyer_id == seller_id
  end

  # The seller must always be the listing's owner — a Transaction records a
  # real sale, not an arbitrary user pairing.
  def seller_matches_listing_owner
    return if listing.blank? || seller_id.blank?

    errors.add(:seller_id, "must be the listing's owner") unless seller_id == listing.user_id
  end

  # The buyer must have an existing conversation with the seller on this
  # listing — this is how the seller "identifies" the real buyer, and it
  # prevents recording an arbitrary user id as the counterparty.
  def buyer_is_conversation_participant
    return if listing_id.blank? || seller_id.blank? || buyer_id.blank?

    exists = Conversation.exists?(listing_id: listing_id, seller_id: seller_id, buyer_id: buyer_id)
    errors.add(:buyer_id, "must be a participant in a conversation on this listing") unless exists
  end
end
