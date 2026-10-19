# SHOP-1 — who may do what with a shop (hatiwal-mobile/docs/SHOPS.md, "Roles").
# Phase 1 has only the owner row; manager/staff follow the spec's role table so
# phase 3 adds members, not rules.
class ShopPolicy < ApplicationPolicy
  EDITORS = %w[owner manager].freeze

  # A suspended/pending shop — or one whose OWNER is suspended (owner, 2026-10-16,
  # computed) — is visible to its own members only.
  def index? = true
  def show? = record.available_to_buyers? || member?
  def create? = user.present?
  def update? = EDITORS.include?(role)
  # SHOP-MEDIA: the shop's photos + video — whoever may edit the shop, while it
  # is not closed (a closed shop's media only waits for its purge).
  def update_media? = update? && !record.closed?
  def destroy? = role == "owner"
  def member? = record.member?(user)
  # SHOP-2: "Message shop" without a product (own shop refused by the service, with its code).
  def message? = user.present? && record.available_to_buyers?
  # privacy-b: block / report a shop by its id — anyone signed in who is not on
  # its team (a member blocking their own shop would block their owner).
  def block? = user.present? && !member?
  def report? = block?
  # Moving listings in or out is managing products: every member may (phase 3).
  def move_listings? = member?
  # SHOP-3 — the team (docs/SHOPS.md, "Permission matrix"): every member sees
  # the list; the owner and managers invite, cancel invites and remove STAFF
  # (Shop#remove_team_member! keeps a manager off managers and the owner).
  def team? = member?
  def manage_team? = EDITORS.include?(role)
  # Owner only: roles and ownership.
  def change_role? = role == "owner"
  def transfer? = role == "owner"
  # Owner decision, 2026-10-08: "if a manager can change the shop's info, they
  # should be able to apply too." The owner OR a manager applies, with their
  # OWN e-Tazkira; the badge then vouches for that applicant (Shop#
  # drop_badge_if_applicant_gone!). Never staff.
  def apply_verification? = EDITORS.include?(role)

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
