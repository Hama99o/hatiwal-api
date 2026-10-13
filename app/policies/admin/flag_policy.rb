# Admin "Flagged listings" (prohibited items, owner 2026-10-13). Only an admin
# account (AdminUser, the /admin session) may see or decide a flag; a decision
# needs the flag to still be open (a second click is refused, not repeated).
class Admin::FlagPolicy < ApplicationPolicy
  def index? = admin?
  def show? = admin?
  def dismiss? = decidable?
  def take_down? = decidable?
  def take_down_warn? = decidable?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.is_a?(AdminUser) ? scope.all : scope.none
    end
  end

  private

  def admin? = user.is_a?(AdminUser)
  def decidable? = admin? && record.open?
end
