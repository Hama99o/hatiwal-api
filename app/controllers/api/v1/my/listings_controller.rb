class Api::V1::My::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [ :show, :update, :destroy, :publish, :unpublish, :reserve, :activate, :sold, :renew ]

  def index
    listings = policy_scope(
      current_user.listings
                  .not_removed
                  .includes(:category, :conversations, :price_histories, images_attachments: :blob)
    ).ordered
    listings = listings.for_status_filter(params[:status]) if params[:status].present?

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

    # Images are handled separately (append + purge) so an edit never wipes the
    # gallery: assigning `images` directly would replace ALL attachments
    # (Rails replace_on_assign_to_many), destroying photos the client didn't
    # re-upload. See attach_new_images / purge_removed_images.
    if @listing.update(listing_params.except(:images))
      attach_new_images
      purge_removed_images
      render_blue(ListingSerializer, @listing, view: :detailed)
    else
      render_unprocessable_entity(@listing)
    end
  end

  def destroy
    authorize @listing

    # Soft-remove instead of hard delete: hides the listing from the feed and
    # My Shop but keeps its conversations/messages, so the buyer's chat history
    # survives (the item just shows as no longer available).
    if @listing.update(removed_at: Time.current, removed_reason: "deleted_by_seller")
      head :no_content
    else
      render_unprocessable_entity(@listing)
    end
  end

  def publish
    authorize @listing, :publish?
    @listing.active!
    @listing.renew! # start the expiry clock
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  # Restart the expiry clock on an active (possibly expired) listing.
  def renew
    authorize @listing, :renew?
    @listing.renew!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  # active → draft (take a published listing offline)
  def unpublish
    authorize @listing, :unpublish?
    @listing.draft!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  # TASK-TX01: optionally accepts `buyer_id` (+ `final_price`) identifying the
  # buyer from one of the listing's conversations — when given, creates or
  # advances the Transaction. Bare calls (no buyer_id) behave exactly as
  # before for backward compatibility with clients already in production.
  def reserve
    authorize @listing, :reserve?
    txn = @listing.reserve_with_buyer!(buyer_id: lifecycle_params[:buyer_id], final_price: lifecycle_params[:final_price])
    @listing.reserved!
    render_lifecycle_response(txn)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  # reserved → active (undo a reservation when a deal falls through)
  def activate
    authorize @listing, :activate?
    @listing.active!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def sold
    authorize @listing, :sold?
    txn = @listing.sold_with_buyer!(buyer_id: lifecycle_params[:buyer_id], final_price: lifecycle_params[:final_price])
    @listing.sold!
    render_lifecycle_response(txn)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  private

  def set_listing
    @listing = current_user.listings.find(params[:id])
  end

  # `buyer_id`/`final_price` are accepted flat (not nested under `listing:`)
  # since reserve/sold are lifecycle commands, not resource updates.
  def lifecycle_params
    params.permit(:buyer_id, :final_price)
  end

  # Composite payload for reserve/sold — always includes the listing; the
  # `transaction` key is present only when a buyer was identified (TASK-TX01).
  def render_lifecycle_response(txn)
    payload = { listing: ListingSerializer.render_as_hash(@listing, view: :detailed) }
    payload[:transaction] = TransactionSerializer.render_as_hash(txn) if txn
    render_ok(payload)
  end

  def listing_params
    params.require(:listing).permit(
      :title, :description, :price, :currency,
      :category_id, :location, :address, :latitude, :longitude, :condition,
      :negotiable,
      images: []
    )
  end

  # Append newly-uploaded photos to the existing gallery (does NOT replace).
  def attach_new_images
    new_images = params.dig(:listing, :images)
    @listing.images.attach(new_images) if new_images.present?
  end

  # Remove only the photos the client explicitly dropped, identified by the
  # blob's signed_id (echoed back from the serializer's image_attachments).
  def purge_removed_images
    signed_ids = params.dig(:listing, :removed_image_ids)
    return if signed_ids.blank?

    Array(signed_ids).each do |signed_id|
      blob = ActiveStorage::Blob.find_signed(signed_id)
      next if blob.nil?

      @listing.images.find_by(blob_id: blob.id)&.purge
    end
  end
end
