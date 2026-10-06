# SHOP-3 — who changed a shop's team, and when (hatiwal-mobile/docs/SHOPS.md,
# "Phase 3 — the team"). Server-side only: the admin shop page lists them; no
# app screen this phase.
class ShopAuditEvent < ApplicationRecord
  ACTIONS = %w[invited invite_cancelled joined declined removed left role_changed transferred].freeze

  belongs_to :shop
  belongs_to :actor, class_name: User.name, optional: true
  belongs_to :target_user, class_name: User.name, optional: true

  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record!(shop, action, actor: nil, target_user: nil, **data)
    create!(shop: shop, action: action.to_s, actor: actor, target_user: target_user, data: data)
  end
end
