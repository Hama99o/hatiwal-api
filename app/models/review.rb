# A rating one party leaves the other after a completed sale. It hangs off a
# sold Transaction (the "who did you sell to?" step is the receipt that
# replaces the payment record Hatiwal doesn't have).
#
# Double-blind: a review is created hidden (`visible: false`) and neither party
# can see the other's rating until BOTH have submitted (revealed together) or
# REVEAL_WINDOW elapses and RevealOverdueReviewsJob reveals the lone review.
# This kills retaliation ("you gave me 2 stars so I'll give you 2 stars").
#
# The association is named `:sale` (not `:transaction`) so it never shadows
# ActiveRecord's `#transaction` DB-transaction method.
class Review < ApplicationRecord
  REVEAL_WINDOW = 14.days

  belongs_to :sale, class_name: Transaction.name, foreign_key: :transaction_id, inverse_of: :reviews
  belongs_to :reviewer, class_name: User.name
  belongs_to :reviewee, class_name: User.name

  # What the reviewee WAS in this sale (the reviewer is always the other side).
  enum :role, { of_seller: 0, of_buyer: 1 }

  validates :rating, presence: true,
                     numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :comment, length: { maximum: 1000 }, allow_blank: true
  validates :reviewer_id, uniqueness: { scope: :transaction_id, message: :already_reviewed }
  validate :sale_is_sold
  validate :parties_are_the_two_sides
  validate :role_matches_reviewee_side

  scope :visible,       -> { where(visible: true) }
  scope :hidden,        -> { where(visible: false) }
  scope :for_reviewee,  ->(user) { where(reviewee_id: user.id) }
  scope :ordered,       -> { order(created_at: :desc) }
  scope :overdue_hidden, -> { hidden.where(created_at: ..REVEAL_WINDOW.ago) }

  # Persist this review and, if the counterparty has already reviewed this sale,
  # reveal BOTH at once. Otherwise it stays hidden until the counterparty
  # submits or RevealOverdueReviewsJob fires. Wrapped in a DB transaction (with a
  # row lock on the counterpart) so two simultaneous submits can't both miss each
  # other and leave the pair permanently hidden.
  def submit!
    self.class.transaction do
      save!
      counterpart = self.class.where(transaction_id: transaction_id).where.not(id: id).lock.first
      if counterpart
        reveal_now!
        counterpart.reveal_now!
      end
    end
    self
  end

  # Flip a single hidden review visible and refresh the reviewee's aggregates.
  # Idempotent — safe for the daily overdue sweep to call on already-visible rows.
  def reveal_now!
    return if visible?

    update!(visible: true, revealed_at: Time.current)
    reviewee.recompute_review_stats!
  end

  private

  def sale_is_sold
    return if sale.blank?

    errors.add(:base, "can only review a completed sale") unless sale.sold?
  end

  def parties_are_the_two_sides
    return if sale.blank? || reviewer_id.blank? || reviewee_id.blank?

    parties = [ sale.buyer_id, sale.seller_id ]
    errors.add(:reviewer_id, "must be a party to the sale") unless parties.include?(reviewer_id)
    unless reviewee_id != reviewer_id && parties.include?(reviewee_id)
      errors.add(:reviewee_id, "must be the other party to the sale")
    end
  end

  def role_matches_reviewee_side
    return if sale.blank? || reviewee_id.blank? || role.blank?

    expected = reviewee_id == sale.seller_id ? "of_seller" : "of_buyer"
    errors.add(:role, "does not match the reviewee's role in the sale") unless role == expected
  end
end
