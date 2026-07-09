class ReviewPolicy < ApplicationPolicy
  # Public list of a user's visible reviews (the controller scopes to :visible).
  def index? = true

  # Sold transactions the caller still owes a review on (My::ReviewsController).
  def pending? = user.present?

  # Only the two parties to a SOLD sale may review it.
  def create?
    sale = record.sale
    return false unless user && sale

    sale.sold? && [ sale.buyer_id, sale.seller_id ].include?(user.id)
  end

  # A review can be edited only by its author, and only while still hidden —
  # once revealed it is locked, so no one can react to the other's score.
  def update?
    user.present? && record.reviewer_id == user.id && !record.visible?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
