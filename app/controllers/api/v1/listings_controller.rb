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
    # A person's profile grid is personal: their shops' products are on the
    # shops' pages (matches users.listings_count). With shop_id, that shop's.
    #
    # Numeric filters go through number_param (hunt-2, 1.1.7): one the client
    # sent in a shape we cannot read is IGNORED, like an unknown `sort`. It
    # used to reach SQL as-is, and price_min=abc answered 500.
    user_id = number_param(:user_id, integer: true)
    shop_id = number_param(:shop_id, integer: true)
    category_id = number_param(:category_id, integer: true)
    price_min = number_param(:price_min)
    price_max = number_param(:price_max)
    seller_active_days = number_param(:seller_active_days, integer: true)

    listings = listings.by_seller(user_id) if user_id
    listings = listings.personal if user_id && shop_id.nil?
    # SHOP-1 — the Bazaar "Shops" filter, and a shop page's Products tab.
    listings = listings.from_shops if params[:seller_type] == Listing::SELLER_TYPE_SHOP
    listings = listings.by_shop(shop_id) if shop_id
    listings = listings.search(params[:search]) if params[:search].present?
    listings = listings.by_category(category_id) if category_id
    listings = listings.by_condition(params[:condition]) if params[:condition].present?
    listings = listings.price_at_least(price_min) if price_min
    listings = listings.price_at_most(price_max) if price_max

    if geo_filter?
      listings = listings.within_radius(*buyer_point, number_param(:radius))
    elsif params[:location].present?
      # Free-text location only when no coordinates are supplied (the mobile app
      # sends a "lat, lng" string as `location` alongside coordinates).
      listings = listings.in_location(params[:location])
    end

    listings = listings.seller_active_within(seller_active_days) if seller_active_days
    listings = listings.with_recent_price_drop if params[:price_dropped].present?

    # Apply sort last so it overrides the :browsable default order.
    # sort=nearest requires latitude/longitude — when present it orders by
    # Haversine distance (composing with any radius filter above). Without
    # coordinates it falls back to the default (newest), same as any other
    # unrecognised value.
    total = nil
    listings = if nearest_sort?
                 total, boxed = nearest_page_scope(listings)
                 boxed.nearest_first(*buyer_point)
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
        shop: { logo_attachment: :blob },
        images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
    )

    paginate_blue(
      ListingSerializer,
      listings,
      # Procs: run on the loaded page (paginate_blue), so each is one lookup on
      # at most a page of ids, not a subquery over the whole feed.
      extra: { view: :list,
               viewed_ids: ->(page) { viewed_listing_ids(page) },
               saved_ids: ->(page) { saved_listing_ids(page) } },
      count: total
    )
  end

  def show
    return render_not_found if blocked_pair_show?
    return render_not_found if removed_for_viewer?
    return render_not_found if closed_shop_for_viewer?
    return render_not_found if blocked_seller_for_viewer?

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
                   { user: { avatar_attachment: :blob }, shop: { logo_attachment: :blob }, images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
                 )
    render_blue_collection(
      ListingSerializer,
      listings,
      view: :list,
      options: { viewed_ids: viewed_listing_ids(listings), saved_ids: saved_listing_ids(listings) }
    )
  end

  private

  # IDs of listings the current user has already opened, among `records` (the
  # rendered page) — one indexed query, used by the serializer to flag each card
  # as "seen". Empty when not signed in.
  #
  # The page's ids, never the unpaginated scope as a subquery: on the feed that
  # subquery re-ran the whole browsable filter (216k rows at 100k users) twice
  # per request, ~370 ms (docs/PERFORMANCE_100K.md).
  def viewed_listing_ids(records)
    return Set.new if current_user.nil?

    current_user.listing_views
                .where(listing_id: records.map(&:id))
                .pluck(:listing_id)
                .to_set
  end

  # TASK-BE-SAVEDLIST — the feed heart's data source. Mirrors viewed_listing_ids
  # exactly: one indexed query (a WHERE listing_id IN subquery), never a
  # per-record `saved_listings.exists?` like the :detailed field uses (that
  # would be an N+1 across a full page). Empty when not signed in — a guest
  # always gets `false` for every row via the serializer's fallback.
  def saved_listing_ids(records)
    return Set.new if current_user.nil?

    current_user.saved_listings
                .where(listing_id: records.map(&:id))
                .pluck(:listing_id)
                .to_set
  end

  def geo_filter?
    buyer_point.present? && number_param(:radius)&.positive?
  end

  # [lat, lng] when both are readable and on the globe, else nil (no radius
  # filter, no nearest sort).
  def buyer_point
    return @buyer_point if defined?(@buyer_point)

    lat = number_param(:latitude)
    lng = number_param(:longitude)
    @buyer_point = (lat && lng && lat.abs <= 90 && lng.abs <= 180) ? [ lat, lng ] : nil
  end

  # A finite number from a query param, or nil when it is missing or unreadable
  # ("abc", "12abc", NaN, Infinity, "1e999", an array or a hash).
  def number_param(key, integer: false)
    raw = params[key]
    return nil unless raw.is_a?(String) || raw.is_a?(Numeric)

    value = integer ? Integer(raw.to_s.strip, 10, exception: false) : Float(raw.to_s.strip, exception: false)
    value if value&.finite?
  end

  # sort=nearest only makes sense with coordinates — radius is optional (the
  # buyer may want "nearest first" across the whole feed, not just within a
  # radius). When coordinates are absent, `sorted` falls back to newest.
  # LOC-1 review — the nearest-first feed without sorting the whole table.
  # Returns [total, scope]: the real total for the pagination meta, and the scope
  # to sort. When the requested page lies entirely among listings WITH a map
  # point, that is just the rows inside the smallest box that already holds the
  # page (Listing.nearest_window_km), so the page is identical to the unboxed
  # sort. Otherwise (a deep page reaching the listings without a point) the
  # whole scope, as before.
  def nearest_page_scope(listings)
    lat, lng = buyer_point
    options = pagy_page_options
    needed = options[:page] * (options[:items] || Pagy::DEFAULT[:items] || 20)
    with_point = listings.where.not(latitude: nil, longitude: nil)
    km = Listing.nearest_window_km(with_point, lat, lng, needed)
    [ listings.count, km ? with_point.within_box(lat, lng, km) : listings ]
  end

  def nearest_sort?
    params[:sort].to_s == "nearest" && buyer_point.present?
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

  # SHOP-1: a suspended / pending / closed shop's products are unavailable to
  # everyone but their seller — the same rule as `browsable`.
  # A banned / suspended seller's listing is gone for everyone but the seller.
  def blocked_seller_for_viewer?
    @listing.user&.account_blocked? && @listing.user_id != current_user&.id
  end

  def closed_shop_for_viewer?
    @listing.shop_id.present? && !@listing.shop&.active? && @listing.user_id != current_user&.id
  end

  def set_listing
    # Unsave only deletes the caller's OWN saved row, so it must work whatever
    # the listing became: a blocked pair's listing is outside the scope, and the
    # card could never be removed from Saved (d0 hunt 2026-10-09).
    scope = action_name == "unsave" ? Listing.all : policy_scope(Listing)
    # Eager-load saved_listings only for #show so the serializer's saves_count
    # (l.saved_listings.size) uses the in-memory association instead of firing
    # a separate COUNT(*) query — avoids an N+1 on the detail endpoint.
    scope = scope.includes(:saved_listings) if action_name == "show"
    @listing = scope.find(params[:id])
  end
end
