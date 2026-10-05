# SHOP-1 — shops (hatiwal-mobile/docs/SHOPS.md).
#
#   GET    /api/v1/shops/:id                 public shop page (guests too)
#   POST   /api/v1/shops                     open your shop (one per user, phase 1)
#   PATCH  /api/v1/shops/:id                 edit (owner / manager)
#   DELETE /api/v1/shops/:id                 delete (owner); its products become personal
#   POST   /api/v1/shops/:id/move_listings   put your listings into the shop, or back
class Api::V1::ShopsController < Api::V1::BaseController
  skip_before_action :authenticate_user!, only: :show
  before_action :authenticate_optional!, only: :show
  before_action :set_shop, except: :create

  # Opening shops is rare; this only stops a script.
  throttle to: 10, within: 1.day, by: :user, only: :create

  def show
    authorize @shop
    view = @shop.member?(current_user) ? :owner : :public
    render_blue(ShopSerializer, @shop, view: view, options: { current_user: current_user })
  end

  def create
    shop = current_user.owned_shops.new(shop_params)
    authorize shop
    if shop.save
      render_blue(ShopSerializer, shop, view: :owner, status: :created, options: { current_user: current_user })
    else
      render_unprocessable_entity(shop, code: shop.error_code)
    end
  end

  def update
    authorize @shop
    if @shop.update(shop_params)
      render_blue(ShopSerializer, @shop, view: :owner, options: { current_user: current_user })
    else
      render_unprocessable_entity(@shop, code: @shop.error_code)
    end
  end

  def destroy
    authorize @shop
    @shop.destroy!
    head :no_content
  end

  # { listing_ids: [..], to: "shop" | "me" } — only the caller's own listings move.
  def move_listings
    authorize @shop
    moved = @shop.move_listings!(current_user, Array(params[:listing_ids]), to_shop: params[:to] != "me")
    render_ok({ moved: moved })
  end

  private

  def set_shop
    @shop = Shop.find(params[:id])
  end

  def shop_params
    permitted = params.require(:shop).permit(
      :name, :description, :category_id, :latitude, :longitude, :province, :city,
      :address_line, :phone, :phone_public, :logo, :cover
    )
    hours = params[:shop][:hours]
    permitted[:hours] = Shop.parse_hours(hours) unless hours.nil?
    permitted
  end
end
