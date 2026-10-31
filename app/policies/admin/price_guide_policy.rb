# Admin "Price guide" (IDEA-4): read-only — the buckets are rebuilt nightly
# from sales, never edited by hand.
class Admin::PriceGuidePolicy < ApplicationPolicy
  def index? = admin?
  def show? = admin?
  def create? = false
  def new? = false
  def update? = false
  def edit? = false
  def destroy? = false

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.is_a?(AdminUser) ? scope.all : scope.none
    end
  end

  private

  def admin? = user.is_a?(AdminUser)
end
