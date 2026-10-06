# SHOP-1 — who may do what with a shop (hatiwal-mobile/docs/SHOPS.md, "Roles").
# Phase 1 has only the owner row; manager/staff follow the spec's role table so
# phase 3 adds members, not rules.
class ShopPolicy < ApplicationPolicy
  EDITORS = %w[owner manager].freeze

  # A suspended or still-pending shop is visible to its own members only.
  def index? = true
  def show? = record.active? || member?
  def create? = user.present?
  def update? = EDITORS.include?(role)
  def destroy? = role == "owner"
  def member? = record.member?(user)
  # SHOP-2: "Message shop" without a product (own shop refused by the service, with its code).
  def message? = user.present? && record.active?
  # Moving listings in or out is managing products: every member may (phase 3).
  def move_listings? = member?
  # SHOP-3 — the team (docs/SHOPS.md, "Permission matrix"): every member sees
  # the list; the owner and managers invite, cancel invites and remove STAFF
  # (Shop#remove_team_member! keeps a manager off managers and the owner).
  def team? = member?
  def manage_team? = EDITORS.include?(role)
  # Owner only: roles, ownership, and the Verified application (it is the
  # owner's own e-Tazkira).
  def change_role? = role == "owner"
  def transfer? = role == "owner"
  def apply_verification? = role == "owner"

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
