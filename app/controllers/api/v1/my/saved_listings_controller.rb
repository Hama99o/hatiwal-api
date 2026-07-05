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
    saved_relation = current_user.saved_listings
                                 .ordered
                                 .includes(listing: [
                                   :category,
                                   :price_histories,
                                   { user: { avatar_attachment: :blob }, images_attachments: :blob }
                                 ])

    # Filled in by the transform block below (which runs BEFORE the response is
    # rendered) with { listing_id => saved_listing } for the current page only.
    # We pass the *same* Hash object through `extra` so the serializer fields
    # can look up the per-save price_at_save/price_dropped/price_drop_amount
    # without a second query — same pattern as `viewed_ids` on ListingsController.
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
