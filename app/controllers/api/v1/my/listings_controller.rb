class Api::V1::My::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [ :show, :update, :destroy, :publish, :reserve, :sold ]

  def index
    listings = policy_scope(current_user.listings).ordered
    listings = listings.where(status: params[:status]) if params[:status].present?

    paginate_blue(ListingSerializer, listings, extra: { view: :seller_list })
  end

  def show
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def create
    @listing = current_user.listings.new(listing_params)
    authorize @listing

    if @listing.save
      render_blue(ListingSerializer, @listing, view: :detailed, status: :created)
    else
      render_unprocessable_entity(@listing)
    end
  end

  def update
    authorize @listing

    if @listing.update(listing_params)
      render_blue(ListingSerializer, @listing, view: :detailed)
    else
      render_unprocessable_entity(@listing)
    end
  end

  def destroy
    authorize @listing

    if @listing.destroy
      head :no_content
    else
      render_unprocessable_entity(@listing)
    end
  end

  def publish
    authorize @listing, :publish?
    @listing.active!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def reserve
    authorize @listing, :reserve?
    @listing.reserved!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def sold
    authorize @listing, :sold?
    @listing.sold!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  private

  def set_listing
    @listing = current_user.listings.find(params[:id])
  end

  def listing_params
    params.require(:listing).permit(
      :title, :description, :price, :currency,
      :category_id, :location, :address, :latitude, :longitude,
      images: []
    )
  end
end
