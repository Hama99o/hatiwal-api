class Api::V1::ListingsController < Api::V1::BaseController
  # Guests can browse the feed and view a listing without logging in. Auth is
  # optional here (resolves current_user if a token is present); save/unsave
  # still require authentication via BaseController.
  skip_before_action :authenticate_user!, only: [ :index, :show ]
  before_action :authenticate_optional!, only: [ :index, :show ]
  before_action :set_listing, only: [ :show, :save, :unsave ]

  def index
    listings = policy_scope(Listing.browsable)
    listings = listings.by_seller(params[:user_id]) if params[:user_id].present?
    listings = listings.search(params[:search]) if params[:search].present?
    listings = listings.by_category(params[:category_id]) if params[:category_id].present?
    listings = listings.by_condition(params[:condition]) if params[:condition].present?
    listings = listings.price_at_least(params[:price_min]) if params[:price_min].present?
    listings = listings.price_at_most(params[:price_max]) if params[:price_max].present?

    if geo_filter?
      listings = listings.within_radius(params[:latitude], params[:longitude], params[:radius])
    elsif params[:location].present?
      # Free-text location only when no coordinates are supplied (the mobile app
      # sends a "lat, lng" string as `location` alongside coordinates).
      listings = listings.in_location(params[:location])
    end

    # Apply sort last so it overrides the :browsable default order.
    # Any absent or unrecognised value silently falls back to newest.
    listings = listings.sorted(params[:sort])

    paginate_blue(
      ListingSerializer,
      listings,
      extra: { view: :list, viewed_ids: viewed_listing_ids(listings) }
    )
  end

  def show
    @listing.increment!(:views_count)
    viewed = current_user ? ListingView.record!(current_user, @listing).present? : false
    render_blue(
      ListingSerializer, @listing,
      view: :detailed,
      options: { current_user: current_user, is_viewed: viewed }
    )
  end

  def save
    authorize @listing, :save?
    saved = current_user.saved_listings.find_or_create_by!(listing: @listing)
    render json: { saved: true, id: saved.id }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  def unsave
    authorize @listing, :save?
    current_user.saved_listings.find_by(listing: @listing)&.destroy
    render json: { saved: false }, status: :ok
  end

  private

  # IDs of listings the current user has already opened, scoped to the current
  # result set — one indexed query, used by the serializer to flag each card as
  # "seen". Empty when not signed in.
  def viewed_listing_ids(scope)
    return Set.new if current_user.nil?

    current_user.listing_views
                .where(listing_id: scope.reorder(nil).select(:id))
                .pluck(:listing_id)
                .to_set
  end

  def geo_filter?
    params[:latitude].present? && params[:longitude].present? && params[:radius].present?
  end

  def set_listing
    @listing = policy_scope(Listing).find(params[:id])
  end
end
