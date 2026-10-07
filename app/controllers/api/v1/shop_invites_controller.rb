# SHOP-3 — the owner's invitations (hatiwal-mobile/docs/SHOPS.md).
#
#   POST   /api/v1/shops/:shop_id/invites            { email? }  no email = a plain link
#   GET    /api/v1/shops/:shop_id/invites            pending first
#   DELETE /api/v1/shops/:shop_id/invites/:id        cancel
#   POST   /api/v1/shops/:shop_id/invites/:id/resend email invites only
#
# 20 invites a day PER SHOP (ShopInvite::DAILY_LIMIT, a 429 with its code):
# the per-user throttle below only stops a script.
class Api::V1::ShopInvitesController < Api::V1::BaseController
  include ShopTeamErrors

  throttle to: 60, within: 1.hour, by: :user, only: %i[create resend]
  before_action :set_shop
  before_action -> { authorize @shop, :manage_team? }

  def create
    invite = @shop.invite!(by: current_user, email: params[:email])
    render_blue(ShopInviteSerializer, invite, view: :owner, status: :created)
  end

  def index
    render_blue_collection(ShopInviteSerializer, @shop.invites.pending_first.limit(100), view: :owner)
  end

  def destroy
    invite = @shop.invites.find(params[:id])
    invite.cancel!(current_user)
    render_blue(ShopInviteSerializer, invite, view: :owner)
  end

  def resend
    invite = @shop.invites.find(params[:id])
    raise ShopInvite::Refused.new(:invite_expired, status: :gone) unless invite.pending? && !invite.expired?
    return render_unprocessable_entity(I18n.t("shops.team.errors.forbidden"), code: :link_invite) if invite.link?

    invitee = User.find_by("LOWER(email) = ?", invite.email)
    if invitee&.confirmed_at.present?
      ShopTeamPushJob.perform_later("shop_invite", invitee.id, @shop.id, current_user.id, nil, invite.id)
      SupportNoticeJob.enqueue(invitee, :shop_invite_received, shop: @shop, invite: invite)
    end
    render_blue(ShopInviteSerializer, invite, view: :owner)
  end

  private

  def set_shop
    @shop = Shop.find(params[:shop_id])
  end
end
