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

    # paginate_blue_with_transform handles the page-number extraction, Pagy call,
    # and response rendering using the house helper — no raw render json: here.
    # The transform block runs filter_map AFTER SQL-level pagination so
    # soft-deleted/removed listings (listing association returns nil) are
    # dropped cleanly from the current page only.
    paginate_blue_with_transform(ListingSerializer, saved_relation, extra: { view: :list }) do |page|
      page.filter_map(&:listing)
    end
  end
end
