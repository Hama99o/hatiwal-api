# VER-1. A person applies for, reads and cancels their OWN request. The
# Support account is staff and never applies. Admin decisions are not here:
# they go through the admin session (Admin::VerificationRequestsController).
class VerificationRequestPolicy < ApplicationPolicy
  # SHOP-3: every member of a shop sees its verification card (read-only);
  # applying and cancelling stay the owner's.
  def show? = record.subject.is_a?(Shop) ? ShopPolicy.new(user, record.subject).member? : owner?
  def create? = owner? && !user.support_account?
  def destroy? = owner? && record.requested?

  class Scope < ApplicationPolicy::Scope
    # SHOP-1: plus the requests of the shops the user manages.
    def resolve
      managed = ShopMember.where(user_id: user.id, role: ShopPolicy::EDITORS).select(:shop_id)
      scope.where(subject: user).or(scope.where(subject_type: Shop.name, subject_id: managed))
    end
  end

  private

  # SHOP-1: for a Shop subject, "owner" = a user who manages that shop
  # (ShopPolicy#update?: owner or manager), and it is still their request.
  def owner?
    return false unless record.requested_by == user

    record.subject.is_a?(Shop) ? ShopPolicy.new(user, record.subject).update? : record.subject == user
  end
end
