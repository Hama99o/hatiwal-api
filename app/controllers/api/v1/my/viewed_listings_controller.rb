class Api::V1::My::ViewedListingsController < Api::V1::BaseController
  def index
    authorize Listing, :viewed?

    # Collect listing IDs that are currently browsable AND pass the blocked-pair
    # guard for the current user. These come straight from the DB as a pluck so
    # we can do a fast include? check in the filter_map block without extra
    # per-row queries.
    browsable_ids = policy_scope(Listing).browsable.pluck(:id).to_set

    # Paginate listing_views at the SQL level (COUNT + OFFSET on listing_views
    # rows) so Pagy metadata is accurate before the filter_map pass.
    # Order by last_viewed_at DESC so the most recently opened item comes first.
    # Eager-load everything the :list serializer view touches to avoid N+1.
    viewed_relation = current_user.listing_views
                                  .order(last_viewed_at: :desc)
                                  .includes(listing: [
                                    :category,
                                    :price_histories,
                                    { user: { avatar_attachment: :blob }, images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
                                  ])

    # paginate_blue_with_transform paginates the listing_views relation at SQL
    # level, then the block runs filter_map to drop any listing that is no longer
    # browsable (sold, draft, expired, removed) or belongs to a blocked pair.
    # No 500 risk: nil listing guard handles hard-deleted records gracefully.
    paginate_blue_with_transform(ListingSerializer, viewed_relation, extra: { view: :list }) do |page|
      page.filter_map do |view|
        listing = view.listing
        next nil if listing.nil?
        next nil unless browsable_ids.include?(listing.id)

        listing
      end
    end
  end
end
