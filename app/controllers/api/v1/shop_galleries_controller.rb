# SHOP-MEDIA (docs/SHOP_MEDIA.md) — the shop's photos, up to 5:
#
#   PUT /api/v1/shops/:shop_id/gallery   multipart: gallery[keep_ids][] (the
#       shop's own photo ids — `gallery_photos[].id` — in the order to show),
#       gallery[photos][] (new image files, appended), like listing[images][]. One save adds, removes and reorders; a photo
#       left out of keep_ids is deleted. Shop#update_gallery! owns the rules.
class Api::V1::ShopGalleriesController < Api::V1::BaseController
  before_action :set_shop

  # The same budget as editing the shop itself (ShopsController#update).
  throttle to: 60, within: 1.hour, by: :user, only: :update

  def update
    authorize @shop, :update_media?

    gallery = params.fetch(:gallery, {})
    if @shop.update_gallery!(keep_ids: gallery[:keep_ids], uploads: gallery[:photos])
      render_blue(ShopSerializer, @shop, view: :owner, options: { current_user: current_user })
    else
      render_unprocessable_entity(@shop)
    end
  end

  private

  def set_shop
    @shop = Shop.find(params[:shop_id])
  end
end
