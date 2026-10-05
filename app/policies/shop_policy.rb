# SHOP-1 — who may do what with a shop (hatiwal-mobile/docs/SHOPS.md, "Roles").
# Phase 1 has only the owner row; manager/staff follow the spec's role table so
# phase 3 adds members, not rules.
class ShopPolicy < ApplicationPolicy
  EDITORS = %w[owner manager].freeze

  # A suspended or still-pending shop is visible to its own members only.
  def show? = record.active? || member?
  def create? = user.present?
  def update? = EDITORS.include?(role)
  def destroy? = role == "owner"
  def member? = record.member?(user)
  # Moving listings in or out is managing products: every member may (phase 3).
  def move_listings? = member?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.visible unless user

      scope.visible.or(scope.where(id: user.shop_members.select(:shop_id)))
    end
  end

  private

  def role
    return nil unless user

    record.shop_members.find_by(user_id: user.id)&.role
  end
end
