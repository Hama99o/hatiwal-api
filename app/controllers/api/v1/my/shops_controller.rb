# SHOP-1 — GET /api/v1/my/shops: the shops the signed-in user works in (phase 1:
# the one they own), for the "Sell as" sheet and the Profile tab's "My shop".
class Api::V1::My::ShopsController < Api::V1::BaseController
  def index
    shops = policy_scope(current_user.shops).recent
                                           .includes(:category, :shop_members, :owner, logo_attachment: :blob, cover_attachment: :blob)
    paginate_blue(ShopSerializer, shops, extra: { view: :owner, current_user: current_user,
                                                  listings_counts: Shop.live_listings_counts(current_user.shop_members.select(:shop_id), viewer: current_user) })
  end
end
