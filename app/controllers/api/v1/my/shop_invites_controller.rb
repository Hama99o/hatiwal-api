# GET /api/v1/my/shop_invites — "My invitations" (owner, 2026-10-06): pending,
# unexpired invitations addressed to the signed-in user's confirmed email, so a
# missed push never loses an invite. Answered through the token endpoints
# (POST /shop_invites/:token/accept | decline).
class Api::V1::My::ShopInvitesController < Api::V1::BaseController
  def index
    authorize ShopInvite
    invites = policy_scope(ShopInvite).includes(:invited_by, shop: { logo_attachment: :blob }).order(created_at: :desc)
    paginate_blue(ShopInviteSerializer, invites, extra: { view: :mine })
  end
end
