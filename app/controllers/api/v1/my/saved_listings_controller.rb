class Api::V1::My::SavedListingsController < Api::V1::BaseController
  def index
    # Eager-load everything the :list serializer view touches, in one go:
    #   - category               → category name fields
    #   - images attachments+blob → thumbnail_url / image_urls
    #   - user + avatar attach.+blob → seller field (u.avatar.attached?/.url)
    #   - price_histories        → price_drop_percent / price_dropped_at
    # Without :price_histories the Listing#recent_price_drop helper falls back
    # to a SQL query per listing row (N+1).
    listings = current_user.saved_listings
                           .ordered
                           .includes(listing: [
                             :category,
                             :price_histories,
                             { user: { avatar_attachment: :blob }, images_attachments: :blob }
                           ])
                           .filter_map(&:listing)

    render_blue_collection(ListingSerializer, listings, view: :list)
  end
end
