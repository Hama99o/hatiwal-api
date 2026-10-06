# SHOP-3 — the team list (hatiwal-mobile/docs/SHOPS.md, "Phase 3 — the team").
#
#   GET    /api/v1/shops/:shop_id/members            every member: owner first, then by join date
#   DELETE /api/v1/shops/:shop_id/members/:user_id   the owner removes a Staff member
#   DELETE /api/v1/shops/:shop_id/membership         a Staff member leaves
class Api::V1::ShopMembersController < Api::V1::BaseController
  include ShopTeamErrors

  before_action :set_shop

  def index
    authorize @shop, :team?
    members = @shop.shop_members.includes(user: { avatar_attachment: :blob })
                   .order(Arel.sql("CASE WHEN shop_members.role = #{ShopMember.roles[:owner].to_i} THEN 0 ELSE 1 END"), :created_at)
    render_blue_collection(ShopMemberSerializer, members)
  end

  def destroy
    authorize @shop, :manage_team?
    @shop.remove_team_member!(User.find(params[:user_id]), by: current_user)
    head :no_content
  end

  def leave
    raise ShopInvite::Refused.new(:not_a_member, status: :forbidden) unless @shop.member?(current_user)

    @shop.leave!(current_user)
    head :no_content
  end

  private

  def set_shop
    @shop = Shop.find(params[:shop_id])
  end
end
