# privacy-b (2026-10-08): block / unblock a shop by ITS id, so a buyer's app
# never needs the owner's user id. Underneath it is a block of the owner (every
# existing block check — chats, offers, pushes — applies unchanged), which
# remembers the shop so the blocked list shows the shop, never the person.
class Api::V1::ShopBlocksController < Api::V1::BaseController
  # Hunt-2 (1.1.7), like BlocksController.
  throttle to: 60, within: 1.hour, by: :user, only: %i[create destroy]

  before_action :set_shop

  # POST /api/v1/shops/:shop_id/block
  def create
    authorize @shop, :block?
    block = Block.find_or_initialize_by(blocker: current_user, blocked: @shop.owner)
    block.shop ||= @shop
    authorize block, :create?
    block.save! if block.new_record? || block.changed?
    head :no_content
  rescue ActiveRecord::RecordNotUnique
    head :no_content
  end

  # DELETE /api/v1/shops/:shop_id/block
  def destroy
    authorize @shop, :block?
    Block.where(blocker: current_user, blocked_id: @shop.owner_id).destroy_all
    head :no_content
  end

  private

  # A closed shop is gone for everyone (ShopsController#show): nothing to block.
  def set_shop
    @shop = Shop.where.not(status: :closed).find_by(id: params[:shop_id])
    render_not_found unless @shop
  end
end
