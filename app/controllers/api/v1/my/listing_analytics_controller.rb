# GET /api/v1/my/listings/:listing_id/analytics
#
# Returns daily view counts for the last 7 days, scoped to the listing owner.
# Each entry contains a date string and a distinct-viewer count for that day.
#
# Response shape:
#   {
#     "analytics": [
#       { "date": "2026-06-11", "count": 0 },
#       ...
#       { "date": "2026-06-17", "count": 3 }
#     ]
#   }
class Api::V1::My::ListingAnalyticsController < Api::V1::BaseController
  before_action :set_listing

  def show
    authorize @listing, :analytics?
    data = ListingView.daily_counts_for_listing(@listing.id)
    render_ok({ analytics: data })
  end

  private

  def set_listing
    @listing = current_user.listings.find(params[:listing_id])
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end
end
