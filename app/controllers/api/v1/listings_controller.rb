class Api::V1::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [ :show, :save, :unsave ]

  def index
    listings = policy_scope(Listing.browsable)
    listings = listings.search(params[:search]) if params[:search].present?
    listings = listings.by_category(params[:category_id]) if params[:category_id].present?
    listings = listings.price_at_least(params[:price_min]) if params[:price_min].present?
    listings = listings.price_at_most(params[:price_max]) if params[:price_max].present?

    if geo_filter?
      listings = listings.within_radius(params[:latitude], params[:longitude], params[:radius])
    elsif params[:location].present?
      # Free-text location only when no coordinates are supplied (the mobile app
      # sends a "lat, lng" string as `location` alongside coordinates).
      listings = listings.in_location(params[:location])
    end

    paginate_blue(ListingSerializer, listings, extra: { view: :list })
  end

  def show
    @listing.increment!(:views_count)
    render_blue(ListingSerializer, @listing, view: :detailed, options: { current_user: current_user })
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

  def geo_filter?
    params[:latitude].present? && params[:longitude].present? && params[:radius].present?
  end

  def set_listing
    @listing = policy_scope(Listing).find(params[:id])
  end
end
