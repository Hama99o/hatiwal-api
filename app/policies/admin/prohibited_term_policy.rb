# Admin "Prohibited terms" (owner, 2026-10-13): any admin account keeps the list.
class Admin::ProhibitedTermPolicy < ApplicationPolicy
  def index? = admin?
  def show? = admin?
  def create? = admin?
  def new? = create?
  def update? = admin?
  def edit? = update?
  def destroy? = admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.is_a?(AdminUser) ? scope.all : scope.none
    end
  end

  private

  def admin? = user.is_a?(AdminUser)
end
