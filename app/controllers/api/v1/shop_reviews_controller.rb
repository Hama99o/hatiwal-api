# GET /api/v1/shops/:shop_id/reviews — the SHOP's reviews (owner, 2026-10-06):
# what buyers wrote about sales of this shop's products (each sale pinned to the
# shop when it was recorded). Never a review of the owner as a buyer, never the
# owner's personal sales. Public, like the shop page; newest first, paginated.
class Api::V1::ShopReviewsController < Api::V1::BaseController
  skip_before_action :authenticate_user!, only: :index
  before_action :authenticate_optional!, only: :index

  def index
    shop = Shop.find(params[:shop_id])
    # Same visibility as the shop page: a closed shop is gone; a suspended or
    # pending one is visible to its members only.
    return render_not_found if shop.closed?

    authorize shop, :show?
    reviews = policy_scope(Review).merge(shop.reviews).ordered.includes(reviewer: { avatar_attachment: :blob })
    paginate_blue(ReviewSerializer, reviews)
  end
end
