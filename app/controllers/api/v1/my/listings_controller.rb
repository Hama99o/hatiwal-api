class Api::V1::My::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [ :show, :update, :destroy, :publish, :unpublish, :reserve, :activate, :sold, :renew ]

  # Feed flooding. A real seller listing 30 items in one day is already an
  # outlier on a local marketplace; a script posting 10 000 is what buries
  # everyone else's listings.
  throttle to: 30, within: 1.day, by: :user, only: :create

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
    # The seller's own search. The mobile app has always SENT this — MyListings
    # debounces the field and passes `search:` to getMyListings, which appends
    # ?search= — and this controller dropped it, so "Search my listings..." typed
    # into a box that did nothing. The public listings controller has applied the
    # same scope since it was written; this one simply never did.
    listings = listings.search(params[:search]) if params[:search].present?

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
    if @listing.update(listing_params.except(:images)) && attach_new_images
      purge_removed_images
      # TASK-R418 (CR fix, CYCLE-4): :owner_detailed — a seller editing the
      # title/description/photos of a RESERVED or SOLD listing must keep
      # seeing the `sale` block in the response, not have it silently
      # disappear because this one action rendered a different view.
      render_blue(ListingSerializer, @listing, view: :owner_detailed)
    else
      # SF-B6: `code:` carries the ONE edit failure the seller has to act on —
      # `quantity_below_sold_units`, when they lowered the quantity under what
      # they have already sold. The `errors` array is unchanged English prose
      # (the fallback for clients that predate the code); the code is what lets a
      # ps/fa client pin its own localized sentence under the quantity field
      # instead of showing a raw Rails string, or worse the generic "server
      # error" this used to 500 with. Nil for every other validation failure, and
      # `render_unprocessable_entity` omits the key then. Listing#error_code owns
      # the mapping — see its note there.
      render_unprocessable_entity(@listing, code: @listing.error_code)
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

    # Listing#publish flips the status AND starts the expiry clock in a single
    # write, so `photo_required_to_publish` can veto the transition and come
    # back as an ordinary 422. The old `active!` + `renew!` pair were bang
    # writes: the moment publishing became refusable they would have raised
    # RecordInvalid and surfaced to the seller as a 500.
    #
    # TASK-R418 (CR fix, CYCLE-4): :owner_detailed everywhere in this
    # controller — see the identical rationale on #create/#update above.
    if @listing.publish
      render_blue(ListingSerializer, @listing, view: :owner_detailed)
    else
      render_unprocessable_entity(@listing)
    end
  end

  # Restart the expiry clock on an active (possibly expired) listing.
  #
  # SF-B7 — the `rescue` is the whole point of this comment, and it is the same
  # rescue #reserve and #sold have always had.
  #
  # `renew!` is a BANG write (`update!`), so any validation failure raises
  # ActiveRecord::RecordInvalid, and nothing in the stack rescues it:
  # ApplicationController only maps Pundit::NotAuthorizedError,
  # ActiveRecord::RecordNotFound and ActionDispatch::ParamError. The seller got a
  # 500 with an EMPTY BODY, and mobile's `apiErrorMessage` falls back to its
  # generic "server error" string on exactly that shape — so the failure was
  # invisible by construction, which is the report this ticket came from.
  #
  # This is reachable for real rows, not theoretical. Every one of Listing's
  # bounds was added AFTER listings already existed — `latitude: 91` "was
  # accepted and persisted" before the coordinate range existed (see its note in
  # listing.rb), and MAX_DESCRIPTION_LENGTH / MAX_IMAGES the same. A legacy row
  # that violates one of them cannot be renewed, unpublished or reactivated, and
  # until now it could not even say why.
  #
  # Deliberately the SAME shape as #reserve/#sold rather than a new one: an
  # ordinary 422 carrying `errors`, which every client already renders.
  def renew
    authorize @listing, :renew?
    @listing.renew!
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  # live → draft (take a published listing offline)
  #
  # SF-B1: reachable from `reserved` too, now that reserving no longer takes a
  # listing out of the feed — "get it off the market while I finish this deal" has
  # to stay a one-step action. Taking it offline cancels any open hold in the same
  # DB transaction, for the same reason #activate does: a draft listing cannot
  # carry a live reservation, and a surviving `reserved` row would later be
  # silently closed out against the wrong buyer (TASK-TX02 review fix, MAJOR).
  #
  # SF-B7: `draft!` is a bang write — rescued into a 422 for the same reason
  # #renew above is. The rescue sits outside the DB transaction, exactly as
  # #reserve/#sold do it, so the cancelled hold is rolled back with the failed
  # status flip and the seller is answered with the field error instead of an
  # empty 500.
  def unpublish
    authorize @listing, :unpublish?
    ActiveRecord::Base.transaction do
      @listing.cancel_open_transaction!
      @listing.draft!
    end
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
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
      # SF-B2: `quantity` passes through here exactly as it already does on
      # #sold, so "2 held for Ahmad" can be a true number on a batch instead of
      # always reading "1". A single-item listing ignores it (see
      # Listing#reserve_with_buyer!).
      txn = @listing.reserve_with_buyer!(
        buyer_id: lifecycle_params[:buyer_id],
        final_price: lifecycle_params[:final_price],
        quantity: lifecycle_params[:quantity]
      )
      # A BATCH does not leave the market because one unit is held. `reserved` is a
      # whole-listing state and `browsable` is `active.not_expired.not_removed`, so
      # flipping it hid all 50 packets from every buyer the moment the seller held one —
      # reported from a device, and the seller's fair question was "how will people buy
      # it?". Reserve is a promise about SOME units; the rest are still for sale.
      #
      # A single-item listing is unchanged: holding it IS taking it off the market, which
      # is exactly what a seller means for one bike.
      @listing.reserved! unless @listing.multi_unit?
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
  #
  # SF-B7: `active!` is a bang write — rescued into a 422, same rationale and
  # same shape as #renew/#unpublish above. This one matters most of the three:
  # releasing a hold is the seller's documented way OUT of SF-B8's refusal, so it
  # must never be the action that dead-ends in an unexplained 500.
  def activate
    authorize @listing, :activate?
    ActiveRecord::Base.transaction do
      @listing.cancel_open_transaction!
      @listing.active!
    end
    # TASK-R418 (CR fix, CYCLE-4): :owner_detailed everywhere in this
    # controller — see #create/#update/#publish above.
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
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
      # TWO fixes here, both reported from a device (50 in stock, one sale, "0 of 50
      # left" and the listing retired).
      #
      # 1. The count must survive the BUYER-LESS path. `sold_with_buyer!` returns nil the
      #    moment clear_buyer is set — before it ever looks at quantity — so a sale to
      #    "someone not on Hatiwal" has no transaction to read the count off, and this
      #    fell straight through to `available_units`.
      # 2. The default for a BATCH is ONE unit, not the whole shelf. "I sold one" is what
      #    a seller means when they say nothing else; "I sold all 50" is a deliberate act
      #    and should be stated. A single-unit listing is untouched: its available_units
      #    IS 1, so the two are the same number.
      #
      # This also protects clients that predate the quantity field — an old build marking
      # a batch sold now moves one unit instead of destroying the stock.
      # SF-B3: `sold_with_buyer!` now ALWAYS returns a sold Transaction — the
      # outside-buyer sale and the bare legacy call included — so its `quantity`
      # is the single source of how many units moved. The controller no longer
      # carries its own duplicate default (`multi_unit? ? 1 : available_units`);
      # that rule lives in Listing#units_for_sale, one copy, so the number in the
      # ledger row and the number taken off the shelf can never disagree.
      sold_out = @listing.record_units_sold!(txn.quantity)
      @listing.sold! if sold_out
      # SF-B3 removed the manual `bump_seller_sold_count_for_legacy_sale!` call
      # that used to sit here: every sale now has a Transaction, and
      # Transaction#bump_trust_counters! counts the seller once. Keeping it would
      # have double-counted every buyer-less sale.
    end
    render_lifecycle_response(txn)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  private

  def set_listing
    @listing = current_user.listings.find(params[:id])
  end

  # `buyer_id`/`final_price`/`clear_buyer`/`quantity` are accepted flat (not
  # nested under `listing:`) since reserve/sold are lifecycle commands, not
  # resource updates. `clear_buyer` (TASK-TX02 review fix) is the sold-only,
  # explicit "Someone else / skip" signal — see Listing#sold_with_buyer!.
  # `quantity` is read by BOTH #reserve (SF-B2, units held) and #sold (units
  # sold); the two actions share this permit list.
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
  # Returns true when there was nothing to attach, or when the attach persisted.
  #
  # Active Storage's `attach` saves the record itself once it is persisted and
  # unchanged, so a file rejected by Listing's attachment validation is silently
  # DROPPED: attach returns, and this request would still render 200 with the
  # photo missing. The explicit `save` is a no-op when attach already persisted
  # the change, and re-runs the validation — returning false with the errors on
  # the record — when it did not.
  def attach_new_images
    new_images = params.dig(:listing, :images)
    return true if new_images.blank?

    @listing.images.attach(new_images)
    @listing.save
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
