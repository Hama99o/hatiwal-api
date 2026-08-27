class TransactionPolicy < ApplicationPolicy
  # Any authenticated user may list their own transaction history — the
  # controller/scope already restricts the collection to rows where the
  # caller is the buyer or the seller.
  def index? = true
  def show?  = user.present? && (record.buyer_id == user.id || record.seller_id == user.id)

  # SF-B4 — correcting or voiding a recorded sale.
  #
  # SELLER ONLY, and only on a SOLD row:
  #   - The seller is the one who recorded the sale, and the one whose stock and
  #     sold_count the correction moves. A buyer must never be able to edit or
  #     erase the other side's ledger entry (they can still refuse to review it).
  #   - `sold?` because a still-RESERVED row is not a sale yet; releasing a hold
  #     is `PUT /my/listings/:id/activate`, which already exists and already
  #     cancels the open transaction. Two doors to the same room would drift.
  def update?  = user.present? && record.seller_id == user.id && record.sold?
  def destroy? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.for_user(user)
    end
  end
end
