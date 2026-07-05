class TransactionPolicy < ApplicationPolicy
  # Any authenticated user may list their own transaction history — the
  # controller/scope already restricts the collection to rows where the
  # caller is the buyer or the seller.
  def index? = true
  def show?  = user.present? && (record.buyer_id == user.id || record.seller_id == user.id)

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.for_user(user)
    end
  end
end
