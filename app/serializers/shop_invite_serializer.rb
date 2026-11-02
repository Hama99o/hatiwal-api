# SHOP-3 — an invitation to join a shop as Staff.
#   :owner   the owner's pending/decided list (with the link to share again)
#   :public  GET /shop_invites/:token, for anyone holding the link: the shop's
#            card, the inviter's name and the state. Nothing else (no email,
#            no member list, no token echo).
class ShopInviteSerializer < ApplicationSerializer
  view :owner do
    fields :id, :email, :role
    field(:status) { |i| i.display_status }
    field(:url) { |i| i.url }
    field(:expires_at) { |i| i.expires_at.iso8601 }
    field(:created_at) { |i| i.created_at.iso8601 }
  end

  # GET /my/shop_invites: an invitation addressed to the viewer. The token is
  # theirs to answer with (POST /shop_invites/:token/accept | decline).
  view :mine do
    fields :id, :role, :token
    field(:shop) { |i| ShopSerializer.render_as_hash(i.shop, view: :card) }
    field(:inviter_name) { |i| i.invited_by.full_name }
    field(:expires_at) { |i| i.expires_at.iso8601 }
    field(:created_at) { |i| i.created_at.iso8601 }
  end

  view :public do
    field(:shop) { |i| ShopSerializer.render_as_hash(i.shop, view: :card) }
    field(:inviter_name) { |i| i.invited_by.full_name }
    field(:role) { |i| i.role }
    field(:status) { |i| i.display_status }
    field(:expires_at) { |i| i.expires_at.iso8601 }
  end
end
