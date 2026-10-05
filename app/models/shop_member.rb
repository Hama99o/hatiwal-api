# SHOP-1 — who works in a shop. Phase 1 has exactly one row per shop, the
# owner's; manager and staff are defined now so phase 3 (team) adds rows and
# rules, not a migration (hatiwal-mobile/docs/SHOPS.md, "Roles").
class ShopMember < ApplicationRecord
  belongs_to :shop
  belongs_to :user
  belongs_to :invited_by, class_name: User.name, optional: true

  enum :role, { owner: 0, manager: 1, staff: 2 }

  validates :user_id, uniqueness: { scope: :shop_id }
end
