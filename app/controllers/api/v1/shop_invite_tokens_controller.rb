# SHOP-3 — opening an invitation (hatiwal-mobile/docs/SHOPS.md, T4–T6).
#
#   GET  /api/v1/shop_invites/:token          PUBLIC: shop card, inviter name, status, expiry
#   POST /api/v1/shop_invites/:token/accept   → { shop_member, me }
#   POST /api/v1/shop_invites/:token/decline
#
# Refusals carry their code: invite_used / invite_cancelled / invite_expired
# (410), invite_wrong_account (403), already_member, shop_unavailable,
# team_full (422).
class Api::V1::ShopInviteTokensController < Api::V1::BaseController
  include ShopTeamErrors

  skip_before_action :authenticate_user!, only: :show
  # Only stops flooding. Guessing is hopeless (192-bit random tokens), and the
  # web's join page fetches through its own server, so every web visitor shares
  # that server's IP: a tight per-IP limit would show valid invites as broken
  # to everyone at once (d8 review of shop-3-web, 2026-10-06).
  throttle to: 600, within: 1.hour, by: :ip, only: :show
  before_action :set_invite

  def show
    render_blue(ShopInviteSerializer, @invite, view: :public)
  end

  def accept
    member = @invite.accept!(current_user)
    render_ok({ shop_member: ShopMemberSerializer.render_as_hash(member),
                me: UserSerializer.render_as_hash(current_user.reload, view: :me) })
  end

  def decline
    @invite.decline!(current_user)
    head :no_content
  end

  private

  def set_invite
    @invite = ShopInvite.includes(:shop, :invited_by).find_by!(token: params[:token].to_s)
  end
end
