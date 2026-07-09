class Api::V1::My::HiddenListingsController < Api::V1::BaseController
  def index
    # Mirrors Api::V1::My::SavedListingsController — paginate the HiddenListing
    # relation at SQL level BEFORE filter_map so Pagy issues a COUNT on
    # HiddenListing rows (not on Listing rows) and LIMIT/OFFSET apply before we
    # load anything into Ruby.
    hidden_relation = current_user.hidden_listings
                                  .ordered
                                  .includes(listing: [
                                    :category,
                                    :price_histories,
                                    { user: { avatar_attachment: :blob }, images_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
                                  ])

    paginate_blue_with_transform(ListingSerializer, hidden_relation, extra: { view: :list }) do |page|
      page.filter_map(&:listing)
    end
  end
end
