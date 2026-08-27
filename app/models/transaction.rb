# A completed (or in-progress) sale between a seller and a buyer for one
# listing. Created/advanced from Listing#reserve_with_buyer! and
# Listing#sold_with_buyer! when the seller identifies the buyer from the
# listing's conversations (TASK-TX01). Legacy reserve/sold calls that omit a
# buyer never touch this table.
class Transaction < ApplicationRecord
  belongs_to :listing
  belongs_to :seller, class_name: User.name
  # SF-B3 — OPTIONAL. `buyer_id` is nil for "sold to someone not on Hatiwal":
  # a real sale, a real ledger row, no counterparty account. Everything that
  # reads a buyer here must be nil-safe (the two validations below already were;
  # TransactionSerializer and ListingSerializer::SALE_FIELD now are too).
  belongs_to :buyer,  class_name: User.name, optional: true

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
  # other attributes on an already-sold row never double-counts.
  #
  # SF-B4 supplied the compensating path this comment used to say did not exist:
  # #void! and #correct! below decrement these counters with a
  # GREATEST(x - 1, 0) floor, so an undone sale gives the count back and a
  # reassigned buyer moves it. Anything new that bumps a counter here needs a
  # matching decrement there.
  #
  # Review fix (TASK-TX02, MED — "no compensating path"): this is safe with
  # respect to the ONE mutation path the mobile client and the public API can
  # reach — `ListingPolicy#sold?` requires `active?`/`reserved?`, so a repeat
  # `PUT .../sold` on an already-sold listing 403s before the bump logic ever
  # runs (see the regression spec "rejects a repeat sold call on an
  # already-sold listing" in spec/requests/api/v1/my/listings_spec.rb).
  #
  # That guarantee does NOT extend to the admin dashboard:
  # `ListingDashboard::FORM_ATTRIBUTES` permits `:status` directly, so an
  # admin CAN flip a Listing's status back and forth via Administrate,
  # bypassing `ListingPolicy` and `Listing#sold_with_buyer!`/`#sold!`
  # entirely.
  #
  # Review fix (TASK-TX02, MED — corrected residual-risk claim): the previous
  # version of this comment claimed that bypass "can't double-count THIS
  # counter" because Administrate only edits a Listing row, never a
  # Transaction row. That is FALSE in effect: flipping a sold Listing back to
  # `active`/`reserved` via the admin re-opens `ListingPolicy#sold?`
  # (`active? || reserved?`), so the seller's normal mobile client can call
  # `PUT .../sold` again — which DOES create/advance a second sold
  # Transaction for the SAME listing, and this callback bumps the live
  # counters a second time. There is no live decrement/guard against it. The
  # real residual risk: after that bypass, sold_count/bought_count can read
  # one higher than the number of listings actually sold, until repaired.
  #
  # Recovery: run `bin/rails transactions:recompute_counters`
  # (lib/tasks/transactions.rake, backed by
  # User#recompute_transaction_counters!), which counts DISTINCT listing_ids
  # rather than raw Transaction rows — so it always restores the correct
  # figure regardless of how many sold Transaction rows a single listing
  # accumulated.
  #
  # Note this counter is also intentionally a LIFETIME stat: it is NOT
  # decremented when a sold listing is later soft-removed, so it can
  # legitimately read higher than the public "Sold" showcase tab (which only
  # lists currently-visible sold listings) — the mobile client accounts for
  # this explicitly (see soldShowcaseEmptyState.ts).
  after_save :bump_trust_counters!, if: -> { sold? && saved_change_to_status? }

  scope :as_buyer,  ->(user) { where(buyer_id: user.id) }
  scope :as_seller, ->(user) { where(seller_id: user.id) }
  scope :for_user,  ->(user) { where("buyer_id = ? OR seller_id = ?", user.id, user.id) }
  scope :ordered,   -> { order(created_at: :desc) }
  # Sales that have a real counterparty account on both sides. SF-B3 made
  # `buyer_id` nullable for "sold to someone not on Hatiwal", so anything that
  # needs two ratable parties (reviews, the pending-review prompt) must say so.
  scope :with_counterparty, -> { where.not(buyer_id: nil) }
  # SF-B5 — one listing's ledger, for the Sales screen
  # (GET /my/transactions?listing_id=42&as=seller&status=sold).
  scope :for_listing, ->(listing_id) { where(listing_id: listing_id) }

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

  # ── SF-B4: correcting and voiding a recorded sale ───────────────────────────
  #
  # Both are reached only through Listing#correct_sold_transaction!, which holds
  # the row locks and keeps `listings.sold_units` in step. Do not call them
  # directly from a controller: on their own they would leave the listing's stock
  # count claiming units this sale no longer accounts for.

  # Edit a recorded sale: its quantity, its price, and/or who it was to.
  #
  # Reassigning the BUYER moves the `bought_count` trust counter — off the person
  # who did not buy it, onto the person who did — with a GREATEST(x - 1, 0) floor
  # so a counter that has already been repaired by
  # `bin/rails transactions:recompute_counters` can never be driven negative.
  #
  # `clear_buyer: true` reuses the exact wire convention #sold established
  # ("reassign to someone not on Hatiwal") rather than inventing a second way to
  # say the same thing.
  def correct!(quantity: nil, buyer_id: nil, clear_buyer: false, final_price: nil)
    new_buyer_id  = clear_buyer ? nil : (buyer_id.presence || self.buyer_id)
    buyer_changed = new_buyer_id.to_i != self.buyer_id.to_i
    raise Listing::CorrectionBlocked, REVIEWED_SALE_ERROR if buyer_changed && reviews.exists?

    old_buyer_id = self.buyer_id
    update!(
      quantity: quantity.presence || self.quantity,
      buyer_id: new_buyer_id,
      final_price: final_price.presence || self.final_price
    )

    return self unless buyer_changed

    decrement_bought_count!(old_buyer_id)
    User.where(id: new_buyer_id).update_all("bought_count = bought_count + 1") if new_buyer_id
    self
  end

  # "This sale did not happen." Removes the row and gives back the trust counters
  # it took — the compensating path TASK-TX02's own comment said did not exist.
  #
  # Only a SOLD row ever bumped a counter, so only a sold row gives one back; a
  # still-reserved row is simply destroyed (that is what
  # Listing#cancel_open_transaction! does, and this stays consistent with it).
  def void!
    raise Listing::CorrectionBlocked, REVIEWED_SALE_ERROR if reviews.exists?

    if sold?
      User.where(id: seller_id).update_all("sold_count = GREATEST(sold_count - 1, 0)")
      decrement_bought_count!(buyer_id)
    end

    destroy!
  end

  # SF-B4 — the one deliberate refusal in the whole correction feature, flagged
  # here so it is never mistaken for an oversight: a sale that already has a
  # review attached can be neither voided nor reassigned to a different buyer.
  # A real, already-written review must not vanish or be re-pointed at someone
  # else because of an unrelated quantity typo. Quantity and price edits on a
  # reviewed sale are still allowed — those do not change who reviewed whom.
  REVIEWED_SALE_ERROR = "This sale already has a review and cannot be removed or reassigned"
  # Machine-readable marker for the 422, so a 3-locale client renders its own
  # copy instead of the English sentence above (mirrors the `account_suspended`
  # convention ApplicationController#reject_blocked_user! already uses).
  REVIEWED_SALE_CODE = "sale_has_review"

  private

  # GREATEST(...) floor, not a bare `- 1`: these counters can already have been
  # rewritten by `bin/rails transactions:recompute_counters`, and a negative
  # trust stat on a public profile is worse than a stale one.
  def decrement_bought_count!(user_id)
    return if user_id.blank?

    User.where(id: user_id).update_all("bought_count = GREATEST(bought_count - 1, 0)")
  end

  # Atomic single-column UPDATEs (no read-then-write race, no extra SELECT) —
  # same reasoning as ActiveRecord's own #increment_counter.
  def bump_trust_counters!
    User.increment_counter(:sold_count, seller_id)
    # SF-B3 — the buyer half is guarded: an outside-buyer sale has no account to
    # credit. The seller's sold_count still moves, because the sale still
    # happened. (`increment_counter` with a nil id would be a no-op UPDATE rather
    # than an error, but relying on that would hide the intent.)
    User.increment_counter(:bought_count, buyer_id) if buyer_id.present?
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
