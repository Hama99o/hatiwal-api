# SHOP-MEDIA (docs/SHOP_MEDIA.md) — a shop's one video, the listing video's
# twin: PUT/DELETE /api/v1/shops/:shop_id/video (VideoUploadActions). Whoever
# may edit the shop (owner, manager); never on a closed shop.
class Api::V1::ShopVideosController < Api::V1::BaseController
  include VideoUploadActions

  before_action :set_shop

  private

  def set_shop
    @shop = Shop.find(params[:shop_id])
  end

  def video_record = @shop

  def authorize_video!(_action)
    authorize @shop, :update_media?
  end

  def render_video_record
    render_blue(ShopSerializer, @shop, view: :owner, options: { current_user: current_user })
  end
end
