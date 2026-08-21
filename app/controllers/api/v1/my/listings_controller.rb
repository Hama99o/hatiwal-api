class Api::V1::My::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [ :show, :update, :destroy, :publish, :unpublish, :reserve, :activate, :sold, :renew ]

  def index
    listings = policy_scope(
      current_user.listings
                  .not_removed
                  .includes(
                    :category, :conversations, :price_histories,
                    # TASK-R418: the :seller_list view's `sale` field reads
                    # listing.current_sale (=> sale_transactions) and its
                    # buyer's avatar — eager-load both so a feed full of
                    # reserved/sold rows stays a constant number of queries.
                    sale_transactions: { buyer: { avatar_attachment: :blob } },
                    images_attachments: { blob: { variant_records: { image_attachment: :blob } } }
                  )
    ).ordered
    listings = listings.for_status_filter(params[:status]) if params[:status].present?

    paginate_blue(ListingSerializer, listings, extra: { view: :seller_list })
  end

  def show
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  end

  def create
    @listing = current_user.listings.new(listing_params)
    authorize @listing

    if @listing.save
      # TASK-R418 (CR fix, CYCLE-4): every owner-scoped single-listing render
      # in this controller uses :owner_detailed, not just show/reserve/sold —
      # a freshly created draft never has a sale (Listing#current_sale
      # returns nil unless reserved?/sold?), so this is a no-op today, but it
      # keeps every response from this controller carrying the exact same
      # shape rather than drifting case-by-case.
      render_blue(ListingSerializer, @listing, view: :owner_detailed, status: :created)
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
      # TASK-R418 (CR fix, CYCLE-4): :owner_detailed — a seller editing the
      # title/description/photos of a RESERVED or SOLD listing must keep
      # seeing the `sale` block in the response, not have it silently
      # disappear because this one action rendered a different view.
      render_blue(ListingSerializer, @listing, view: :owner_detailed)
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
    # TASK-R418 (CR fix, CYCLE-4): :owner_detailed everywhere in this
    # controller — see the identical rationale on #create/#update above.
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  end

  # Restart the expiry clock on an active (possibly expired) listing.
  def renew
    authorize @listing, :renew?
    @listing.renew!
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  end

  # active → draft (take a published listing offline)
  def unpublish
    authorize @listing, :unpublish?
    @listing.draft!
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  end

  # TASK-TX01: optionally accepts `buyer_id` (+ `final_price`) identifying the
  # buyer from one of the listing's conversations — when given, creates or
  # advances the Transaction. Bare calls (no buyer_id) behave exactly as
  # before for backward compatibility with clients already in production.
  #
  # Review fix (TASK-TX02, CR LOW): the Transaction write and the Listing
  # status flip are wrapped in one DB transaction — if `reserved!` ever raised
  # (e.g. a future validation) after `reserve_with_buyer!` already persisted,
  # the Transaction would otherwise be left committed as "reserved" for a
  # listing that never actually became `reserved`. All-or-nothing instead.
  def reserve
    authorize @listing, :reserve?
    txn = nil
    ActiveRecord::Base.transaction do
      txn = @listing.reserve_with_buyer!(buyer_id: lifecycle_params[:buyer_id], final_price: lifecycle_params[:final_price])
      @listing.reserved!
    end
    render_lifecycle_response(txn)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  # reserved → active (undo a reservation when a deal falls through)
  #
  # Review fix (TASK-TX02, MAJOR — "activate never touches the Transaction"):
  # the deal falling through must cancel any open reservation, or a stale
  # `reserved` Transaction row survives and can later be silently closed out
  # to `sold` against the wrong buyer by a subsequent buyer-less `sold` call
  # (see Listing#sold_with_buyer!). Wrapped in one DB transaction for the same
  # all-or-nothing reasoning as #reserve/#sold below.
  def activate
    authorize @listing, :activate?
    ActiveRecord::Base.transaction do
      @listing.cancel_open_transaction!
      @listing.active!
    end
    # TASK-R418 (CR fix, CYCLE-4): :owner_detailed everywhere in this
    # controller — see #create/#update/#publish above.
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  end

  # Review fix (TASK-TX02, CR LOW — "wrap sold_with_buyer! + sold! in a
  # transaction"): same all-or-nothing reasoning as #reserve above. Without
  # this, a `sold!` failure after `sold_with_buyer!` already advanced/created
  # a Transaction to `sold` (bumping trust counters via
  # Transaction#bump_trust_counters!) would strand a "sold" Transaction on a
  # Listing that never actually reached `sold` — counters bumped for a sale
  # that, from the Listing's own status, never happened.
  def sold
    authorize @listing, :sold?
    txn = nil
    ActiveRecord::Base.transaction do
      txn = @listing.sold_with_buyer!(
        buyer_id: lifecycle_params[:buyer_id],
        final_price: lifecycle_params[:final_price],
        clear_buyer: ActiveModel::Type::Boolean.new.cast(lifecycle_params[:clear_buyer]),
        quantity: lifecycle_params[:quantity]
      )

      # Multi-quantity (docs/SPIKE_LISTING_QUANTITY.md): record the units and only
      # retire the listing once the stock is actually empty. A listing with 13 of
      # 15 left MUST stay `active` and browsable — flipping it to `sold` here is
      # what would have broken the feed, and it is the single most important line
      # in this feature.
      sold_out = @listing.record_units_sold!(txn&.quantity || @listing.available_units)
      @listing.sold! if sold_out
      # TASK-TX02 (review fix): the legacy buyer-less path (txn is nil) never
      # touches the transactions table, so nothing else bumps the seller's
      # trust-stat counter for it — do it here, once, explicitly.
      @listing.bump_seller_sold_count_for_legacy_sale! if txn.nil?
    end
    render_lifecycle_response(txn)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  private

  def set_listing
    @listing = current_user.listings.find(params[:id])
  end

  # `buyer_id`/`final_price`/`clear_buyer` are accepted flat (not nested under
  # `listing:`) since reserve/sold are lifecycle commands, not resource
  # updates. `clear_buyer` (TASK-TX02 review fix) is the sold-only, explicit
  # "Someone else / skip" signal — see Listing#sold_with_buyer!.
  def lifecycle_params
    params.permit(:buyer_id, :final_price, :clear_buyer, :quantity)
  end

  # Composite payload for reserve/sold — always includes the listing; the
  # `transaction` key is present only when a buyer was identified (TASK-TX01).
  # TASK-R418: the listing is rendered with :owner_detailed (not :detailed) so
  # the response's own `listing.sale` already reflects the just-recorded
  # buyer — no client-side merge of `transaction` into the listing needed.
  def render_lifecycle_response(txn)
    payload = { listing: ListingSerializer.render_as_hash(@listing, view: :owner_detailed) }
    payload[:transaction] = TransactionSerializer.render_as_hash(txn) if txn
    render_ok(payload)
  end

  def listing_params
    params.require(:listing).permit(
      :title, :description, :price, :currency,
      :category_id, :location, :address, :latitude, :longitude, :condition,
      :negotiable, :quantity,
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
