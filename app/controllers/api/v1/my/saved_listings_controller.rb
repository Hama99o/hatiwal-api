class Api::V1::My::SavedListingsController < Api::V1::BaseController
  def index
    # Paginate the SavedListing relation at SQL level BEFORE filter_map so
    # Pagy issues a COUNT on SavedListing rows (not on Listing rows) and
    # LIMIT/OFFSET apply before we load anything into Ruby.
    #
    # Eager-load everything the :list serializer view touches, in one go:
    #   - category               → category name fields
    #   - images attachments+blob → thumbnail_url / image_urls
    #   - user + avatar attach.+blob → seller field (u.avatar.attached?/.url)
    #   - price_histories        → price_drop_percent / price_dropped_at
    # Without :price_histories the Listing#recent_price_drop helper falls back
    # to a SQL query per listing row (N+1).
    # Only what the user can still OPEN (the same rules as ListingsController#
    # show): not a removed listing, not a blocked pair (either way), not a
    # product of a shop that isn't active — each of those 404'd on tap (d0 hunt
    # 2026-10-09). The viewer's own listings always show. Sold ones stay: they
    # still open. Filtered in SQL, so the page count stays right.
    uid = current_user.id
    openable = Listing.excluding_blocked_pairs(current_user)
                      .where("listings.removed_at IS NULL OR listings.user_id = ?", uid)
                      .where("listings.shop_id IS NULL OR listings.user_id = ? OR listings.shop_id IN (?)",
                             uid, Shop.active.select(:id))
    saved_relation = current_user.saved_listings
                                 .joins(:listing).merge(openable)
                                 .ordered
                                 .includes(listing: [
                                   :category,
                                   :price_histories,
                                   # SF-B2 — preloaded for the base `held_units` field; see
                                   # Listing#open_sale's loaded-array guard.
                                   :sale_transactions,
                                   { user: { avatar_attachment: :blob }, shop: { logo_attachment: :blob }, images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
                                 ])

    # Filled in by the transform block below (which runs BEFORE the response is
    # rendered) with { listing_id => saved_listing } for the current page only.
    # We pass the *same* Hash object through `extra` so the serializer fields
    # can look up the per-save price_at_save/price_dropped/price_drop_amount
    # without a second query — same pattern as `viewed_ids` on ListingsController.
    # TASK-BE-SAVEDLIST: the serializer's `is_saved` field also reads this same
    # map — every row this screen renders IS a saved listing by construction,
    # so a key hit is proof enough; no separate `saved_ids:` Set needed here.
    saved_by_listing_id = {}

    # paginate_blue_with_transform handles the page-number extraction, Pagy call,
    # and response rendering using the house helper — no raw render json: here.
    # The transform block runs filter_map AFTER SQL-level pagination so
    # soft-deleted/removed listings (listing association returns nil) are
    # dropped cleanly from the current page only.
    paginate_blue_with_transform(
      ListingSerializer,
      saved_relation,
      extra: { view: :list, saved_by_listing_id: saved_by_listing_id }
    ) do |page|
      page.filter_map do |saved_listing|
        listing = saved_listing.listing
        next nil if listing.nil?

        saved_by_listing_id[listing.id] = saved_listing
        listing
      end
    end
  end
end
