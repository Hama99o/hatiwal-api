class Api::V1::ListingsController < Api::V1::BaseController
  # Guests can browse the feed and view a listing without logging in. Auth is
  # optional here (resolves current_user if a token is present); save/unsave
  # still require authentication via BaseController.
  skip_before_action :authenticate_user!, only: [ :index, :show, :similar ]
  before_action :authenticate_optional!, only: [ :index, :show, :similar ]
  before_action :set_listing, only: [ :show, :save, :unsave, :similar, :hide, :unhide ]

  def index
    # This feed is browsable-only BY DEFINITION: `browsable` is
    # active.not_expired.not_removed, so there is no `status` filter here and
    # none is wanted — a public feed does not show drafts or sold stock.
    #
    # Worth stating because both clients send `status` to this endpoint and it is
    # silently dropped. Today that is harmless (they send "active", which is what
    # browsable already means), but the mobile app and the web app each carried a
    # comment reasoning about what `status` does here, so the next person to want
    # a "sold" tab would have reached for `status=sold` and got a full page of
    # ACTIVE listings back. Sold stock has its own endpoint:
    # GET /users/:id/sold_listings.
    listings = policy_scope(Listing.browsable)
    listings = listings.not_hidden_for(current_user)
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

    listings = listings.seller_active_within(params[:seller_active_days]) if params[:seller_active_days].present?
    listings = listings.with_recent_price_drop if params[:price_dropped].present?

    # Apply sort last so it overrides the :browsable default order.
    # sort=nearest requires latitude/longitude — when present it orders by
    # Haversine distance (composing with any radius filter above). Without
    # coordinates it falls back to the default (newest), same as any other
    # unrecognised value.
    listings = if nearest_sort?
                 listings.nearest_first(params[:latitude], params[:longitude])
    else
                 listings.sorted(params[:sort])
    end
    # TASK-API-FEEDN1 — the ONE include list the :list view actually needs, on the
    # busiest public endpoint in the app. It is deliberately identical to
    # #similar's list below (and to my/saved_listings, my/viewed_listings,
    # my/hidden_listings, users/sold_listings, all of which already had it):
    # every one of them renders the SAME :list view, so a divergent include list
    # here is not a local tuning choice, it is a bug.
    #
    # This endpoint used to preload `:price_histories, :sale_transactions` only,
    # while :list also reads `l.user` + that user's avatar blob (the `seller`
    # field), `l.category`, and the images attachments behind `thumbnail_url` /
    # `image_urls`. Each of those is an unloaded association read from inside a
    # serializer block, so each cost one query PER CARD — roughly 80 extra
    # queries on a 20-card page, on the first screen every buyer sees, over
    # Afghan mobile networks.
    #
    # Field-by-field, why each entry is here (and nothing more is):
    #   :category           -> field(:category) { CategorySerializer... }
    #   :price_histories    -> price_drop_percent / price_dropped_at
    #                          (Listing#recent_price_drop's loaded-array guard)
    #   :sale_transactions  -> the base `held_units` / `sales_count` fields
    #                          (SF-B2; Listing#open_sale's loaded-array guard)
    #   user + avatar blob  -> field(:seller) { u.avatar.attached? ? u.avatar.url }
    #   images + variants   -> thumbnail_url (a lazy variant URL, which reads
    #                          blob.variable? and the variant records) + image_urls
    #
    # NOT preloaded on purpose: `:conversations` and `:saved_listings`. :list
    # renders neither (`conversations_count` is :seller_list/:detailed,
    # `saves_count` is :detailed) — preloading them here would trade one wasted
    # query per card for two wasted table loads per page.
    listings = listings.includes(
      :category,
      :price_histories,
      :sale_transactions,
      { user: { avatar_attachment: :blob },
        images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
    )

    paginate_blue(
      ListingSerializer,
      listings,
      extra: { view: :list, viewed_ids: viewed_listing_ids(listings), saved_ids: saved_listing_ids(listings) }
    )
  end

  def show
    return render_not_found if blocked_pair_show?
    return render_not_found if removed_for_viewer?

    @listing.register_view!(current_user)
    viewed = current_user ? ListingView.exists?(user_id: current_user.id, listing_id: @listing.id) : false
    render_blue(
      ListingSerializer, @listing,
      view: :detailed,
      options: { current_user: current_user, is_viewed: viewed }
    )
  end

  def save
    authorize @listing, :save?
    saved = current_user.saved_listings.find_or_create_by!(listing: @listing)
    render_ok({ saved: true, id: saved.id })
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  def unsave
    authorize @listing, :save?
    current_user.saved_listings.find_by(listing: @listing)&.destroy
    render_ok({ saved: false })
  end

  # "Not interested" — hides the listing from the current user's own Browse
  # feed only. Distinct from save/unsave and from the seen/viewed dim badge.
  def hide
    authorize @listing, :hide?
    hidden = current_user.hidden_listings.find_or_create_by!(listing: @listing)
    render_ok({ hidden: true, id: hidden.id })
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  def unhide
    authorize @listing, :unhide?
    current_user.hidden_listings.find_by(listing: @listing)&.destroy
    render_ok({ hidden: false })
  end

  def similar
    authorize @listing, :similar?
    # not_hidden_for: a cross-sell rail must respect "Not interested" exactly like
    # the feed does — re-offering something the viewer explicitly dismissed reads
    # as the app not listening. No-op for guests.
    listings = policy_scope(Listing.similar_to(@listing))
                 .not_hidden_for(current_user)
                 .includes(
                   :category,
                   :price_histories,
                   # SF-B2 — preloaded for the base `held_units` field; see
                   # Listing#open_sale's loaded-array guard.
                   :sale_transactions,
                   { user: { avatar_attachment: :blob }, images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
                 )
    render_blue_collection(
      ListingSerializer,
      listings,
      view: :list,
      options: { viewed_ids: viewed_listing_ids(listings), saved_ids: saved_listing_ids(listings) }
    )
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

  # TASK-BE-SAVEDLIST — the feed heart's data source. Mirrors viewed_listing_ids
  # exactly: one indexed query (a WHERE listing_id IN subquery), never a
  # per-record `saved_listings.exists?` like the :detailed field uses (that
  # would be an N+1 across a full page). Empty when not signed in — a guest
  # always gets `false` for every row via the serializer's fallback.
  def saved_listing_ids(scope)
    return Set.new if current_user.nil?

    current_user.saved_listings
                .where(listing_id: scope.reorder(nil).select(:id))
                .pluck(:listing_id)
                .to_set
  end

  def geo_filter?
    params[:latitude].present? && params[:longitude].present? && params[:radius].present?
  end

  # sort=nearest only makes sense with coordinates — radius is optional (the
  # buyer may want "nearest first" across the whole feed, not just within a
  # radius). When coordinates are absent, `sorted` falls back to newest.
  def nearest_sort?
    params[:sort].to_s == "nearest" && params[:latitude].present? && params[:longitude].present?
  end

  # Returns true when a logged-in, non-owner viewer is in a mutual block
  # relationship with the listing's seller. Guests and the listing owner
  # are always allowed through.
  def blocked_pair_show?
    return false if current_user.nil?
    return false if @listing.user_id == current_user.id

    current_user.blocked?(@listing.user) || current_user.blocked_by?(@listing.user)
  end

  # A listing taken down by an admin is hidden from everyone except its owner
  # (who can still see it — e.g. to learn it was removed).
  def removed_for_viewer?
    @listing.removed? && @listing.user_id != current_user&.id
  end

  def set_listing
    scope = policy_scope(Listing)
    # Eager-load saved_listings only for #show so the serializer's saves_count
    # (l.saved_listings.size) uses the in-memory association instead of firing
    # a separate COUNT(*) query — avoids an N+1 on the detail endpoint.
    scope = scope.includes(:saved_listings) if action_name == "show"
    @listing = scope.find(params[:id])
  end
end
