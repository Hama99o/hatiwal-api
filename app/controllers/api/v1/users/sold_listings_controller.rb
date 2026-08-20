# frozen_string_literal: true

# GET /api/v1/users/:user_id/sold_listings
#
# Public endpoint — works for guests (mirrors the authenticate_optional! pattern
# used by ListingsController#index). Returns a paginated list of sold listings
# for a publicly-active seller. Returns 404 if the seller account is deleted or
# pending deletion.
class Api::V1::Users::SoldListingsController < Api::V1::BaseController
  skip_before_action :authenticate_user!
  before_action :authenticate_optional!

  def index
    seller = User.publicly_active.find(params[:user_id])

    authorize Listing, :sold_by?

    listings = policy_scope(Listing)
                 .where(user_id: seller.id)
                 .sold
                 .not_removed
                 .ordered
                 .includes(
                   :category,
                   :price_histories,
                   { user: { avatar_attachment: :blob }, images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
                 )

    # TASK-BE-SAVEDLIST (FlowApp #255) — no `saved_ids:` fed here, so the
    # serializer's `is_saved` falls back to `false` for every row. Deliberate
    # scope decision (documented, not an oversight): this is a public seller
    # profile rail (someone else's sold history), not the buyer's own
    # browse/saved/similar surfaces the card asked to prioritize.
    paginate_blue(ListingSerializer, listings, extra: { view: :list })
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end
end
