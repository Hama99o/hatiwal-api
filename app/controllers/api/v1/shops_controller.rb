# SHOP-1 — shops (hatiwal-mobile/docs/SHOPS.md).
#
#   GET    /api/v1/shops/:id                 public shop page (guests too)
#   POST   /api/v1/shops                     open a shop (several per user, never the same twice: SHOP-2)
#   PATCH  /api/v1/shops/:id                 edit (owner / manager)
#   DELETE /api/v1/shops/:id                 close (owner): soft, Shop#close!; its products become personal
#   POST   /api/v1/shops/:id/move_listings   put your listings into the shop, or back
class Api::V1::ShopsController < Api::V1::BaseController
  skip_before_action :authenticate_user!, only: %i[index show]
  before_action :authenticate_optional!, only: %i[index show]
  before_action :set_shop, except: %i[index create]

  # Opening shops is rare; this only stops a script.
  throttle to: 10, within: 1.day, by: :user, only: :create
  # Owner rule (1.1.6): a confirmed email before opening a shop.
  before_action :require_confirmed_email!, only: :create

  # GET /api/v1/shops[?verified=true] — open shops, for the web sitemap
  # (verified ones go in it). Minimal rows; paginated.
  def index
    authorize Shop
    shops = policy_scope(Shop).visible.order(updated_at: :desc)
    shops = shops.where.not(verified_at: nil) if ActiveModel::Type::Boolean.new.cast(params[:verified])
    paginate_blue(ShopSerializer, shops, extra: { view: :sitemap })
  end

  def show
    # A closed shop is gone for everyone, its former owner included.
    return render_not_found if @shop.closed?

    authorize @shop
    view = @shop.member?(current_user) ? :owner : :public
    render_blue(ShopSerializer, @shop, view: view, options: { current_user: current_user })
  end

  def create
    shop = current_user.owned_shops.new(shop_params)
    authorize shop
    saved = Shop.transaction do
      Shop.lock_owner!(current_user.id)
      shop.save
    end
    if saved
      render_blue(ShopSerializer, shop, view: :owner, status: :created, options: { current_user: current_user })
    else
      render_shop_errors(shop)
    end
  end

  def update
    authorize @shop
    saved = Shop.transaction do
      Shop.lock_owner!(@shop.owner_id)
      @shop.update(shop_params)
    end
    if saved
      # A verified shop's new name/address is not what the badge vouched for.
      SupportNoticeJob.enqueue(@shop.owner, :shop_reverify_needed, shop: @shop) if @shop.drop_badge_after_identity_change!
      render_blue(ShopSerializer, @shop, view: :owner, options: { current_user: current_user })
    else
      render_shop_errors(@shop)
    end
  end

  def destroy
    authorize @shop
    @shop.close!
    head :no_content
  end

  # { listing_ids: [..], to: "shop" | "me" } — only the caller's own listings move.
  def move_listings
    authorize @shop
    to_shop = params[:to] != "me"
    return render_unprocessable_entity(I18n.t("shops.errors.not_open"), code: :shop_not_open) if to_shop && !@shop.active?

    moved = @shop.move_listings!(current_user, Array(params[:listing_ids]), to_shop: to_shop)
    render_ok({ moved: moved })
  end

  private

  # SHOP-2: a duplicate names the shop it duplicates, so the app can offer it.
  def render_shop_errors(shop)
    extra = shop.duplicate_shop ? { duplicate_shop_id: shop.duplicate_shop.id } : {}
    render_unprocessable_entity(shop, code: shop.error_code, extra: extra)
  end

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
