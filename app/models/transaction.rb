# A completed (or in-progress) sale between a seller and a buyer for one
# listing. Created/advanced from Listing#reserve_with_buyer! and
# Listing#sold_with_buyer! when the seller identifies the buyer from the
# listing's conversations (TASK-TX01). Legacy reserve/sold calls that omit a
# buyer never touch this table.
class Transaction < ApplicationRecord
  belongs_to :listing
  belongs_to :seller, class_name: User.name
  belongs_to :buyer,  class_name: User.name

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
