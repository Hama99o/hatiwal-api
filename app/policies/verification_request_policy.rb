# VER-1. A person applies for, reads and cancels their OWN request. The
# Support account is staff and never applies. Admin decisions are not here:
# they go through the admin session (Admin::VerificationRequestsController).
class VerificationRequestPolicy < ApplicationPolicy
  def show? = owner?
  def create? = owner? && !user.support_account?
  def destroy? = owner? && record.requested?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(subject: user)
  end

  private

  def owner? = record.subject == user && record.requested_by == user
end
