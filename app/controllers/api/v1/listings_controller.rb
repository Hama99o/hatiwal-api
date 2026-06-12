class Api::V1::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [:show, :save, :unsave]

  def index
    listings = policy_scope(Listing.browsable)
    listings = listings.search(params[:search]) if params[:search].present?
    listings = listings.by_category(params[:category_id]) if params[:category_id].present?

    paginate_blue(ListingSerializer, listings, extra: { view: :list })
  end

  def show
    @listing.increment!(:views_count)
    render_blue(ListingSerializer, @listing, view: :detailed)
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

  def set_listing
    @listing = policy_scope(Listing).find(params[:id])
  end
end
