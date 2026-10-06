# SHOP-3 — the team list (hatiwal-mobile/docs/SHOPS.md, "Phase 3 — the team").
#
#   GET    /api/v1/shops/:shop_id/members            every member: owner first, then by join date
#   DELETE /api/v1/shops/:shop_id/members/:user_id   the owner removes a Staff member
#   DELETE /api/v1/shops/:shop_id/membership         a Staff member or a manager leaves
#   PATCH  /api/v1/shops/:shop_id/members/:user_id   { role: "manager"|"staff" } (owner)
#   POST   /api/v1/shops/:shop_id/transfer           { user_id } (owner) → { shop, me }
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

  def update
    authorize @shop, :change_role?
    member = @shop.change_role!(User.find(params[:user_id]), role: params[:role], by: current_user)
    render_blue(ShopMemberSerializer, member)
  end

  def transfer
    authorize @shop, :transfer?
    @shop.transfer_ownership!(User.find(params[:user_id]), by: current_user)
    # The caller's own new role (manager) without a refetch race (apps-6a).
    render_ok({ shop: ShopSerializer.render_as_hash(@shop, view: :owner, current_user: current_user),
                me: UserSerializer.render_as_hash(current_user.reload, view: :me) })
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
