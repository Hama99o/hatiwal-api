class Api::V1::My::SavedListingsController < Api::V1::BaseController
  def index
    saved = current_user.saved_listings.ordered.includes(:listing)
    listings = saved.map(&:listing).compact

    render json: {
      listings: ListingSerializer.render_as_hash(listings, view: :list),
      meta: { total_count: listings.count }
    }
  end
end
