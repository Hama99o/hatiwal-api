# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 2;
# design: hatiwal-mobile docs/design/SELLER_ANALYTICS.md): a seller's numbers,
# for ONE identity — the person (Me) or one shop, seen by its members (staff
# included). Never summed across identities, never site-wide.
#
#   GET  /my/analytics?shop_id=<id>            (none / blank = Me)
#   POST /my/listings/relaunch_expired {shop_id}
class Api::V1::My::AnalyticsController < Api::V1::BaseController
  before_action :set_identity

  def show
    authorize Listing, :seller_analytics?

    listings = @listings.not_removed
    raw      = listings.group(:status).count
    expired  = listings.expired_active.count
    live     = (raw["active"] || 0) + (raw["reserved"] || 0)

    render_ok({ analytics: {
      shop: @shop && ShopSerializer.render_as_hash(@shop, view: :card),
      # Every listing not removed: drafts, live, expired and sold.
      total: listings.count,
      # The My listings tabs: Active = live and not expired; Expired = live past its run.
      active: live - expired,
      expired: expired,
      sold: raw["sold"] || 0,
      draft: raw["draft"] || 0,
      # Recorded sales (a batch can sell many times before it is sold out).
      sales: sales.count,
      units_sold: sales.sum(:quantity),
      views: listings.sum(:views_count),
      # Chats begun with THIS identity (pinned at start; a moved listing's old
      # chats stay where they began).
      chats: chats.count
    } })
  end

  # "Relaunch all" from the Expired tile: one-tap Renew for every expired
  # listing of this identity (+LISTING_LIFESPAN, never bumps). A row that fails
  # validation (a legacy listing invalid under a later rule) is counted, not raised.
  def relaunch_expired
    authorize Listing, :seller_analytics?

    renewed = failed = 0
    @listings.not_removed.expired_active.find_each do |listing|
      listing.renew!
      renewed += 1
    rescue ActiveRecord::RecordInvalid
      failed += 1
    end
    render_ok({ renewed: renewed, failed: failed })
  end

  private

  # Me, or a shop the caller is on (any role). Nothing else.
  def set_identity
    shop_id = params[:shop_id].presence
    if shop_id.nil? || shop_id == "me"
      @shop = nil
      @listings = current_user.listings.where(shop_id: nil)
    else
      @shop = Shop.find_by(id: shop_id)
      return render_coded_error("you are not on that shop's team", code: :not_a_member, status: :forbidden) unless @shop&.member?(current_user)

      @listings = @shop.listings
    end
  end

  def sales
    scope = Transaction.sold
    @shop ? scope.where(shop_id: @shop.id) : scope.where(shop_id: nil, seller_id: current_user.id)
  end

  def chats
    scope = Conversation.kind_listing
    @shop ? scope.where(shop_id: @shop.id) : scope.where(shop_id: nil, seller_id: current_user.id)
  end
end
