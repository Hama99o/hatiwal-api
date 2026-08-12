class Api::V1::CategoriesController < Api::V1::BaseController
  # Public reference data — guests browsing the feed need the category chips.
  skip_before_action :authenticate_user!, only: [ :index ]
  before_action :authenticate_optional!, only: [ :index ]

  def index
    authorize Category, :index?

    categories = Category.active.ordered.top_level.includes(:subcategories)

    if params[:with_counts].present?
      render_blue_collection(CategorySerializer, categories, view: :with_counts,
                             options: { counts_by_id: hub_listing_counts(categories) })
    else
      render_blue_collection(CategorySerializer, categories, view: :with_subcategories)
    end
  end

  private

  # Browsable-listing counts for every row the category hub renders — parents
  # *and* their subcategories — computed in ONE GROUP BY query (no per-category
  # SQL, no N+1).
  #
  # A parent's count rolls its subcategories' counts up, because a listing filed
  # under "Electronics > Phones" is an Electronics listing: `Listing.by_category`
  # returns it when you filter by Electronics, so the hub number must include it
  # or the card would under-report the inventory sitting behind it.
  #
  # The count is taken from the SAME scope the feed uses
  # (`policy_scope(Listing.browsable).not_hidden_for(current_user)` — see
  # ListingsController#index), so a hub card can never promise listings that
  # `?category_id=` then filters out for this viewer (blocked users, "not
  # interested").
  def hub_listing_counts(categories)
    # Every child, not just the visible ones: `Category.self_and_children` — what
    # `by_category` filters on — ignores `active`, so a listing parked under a
    # deactivated subcategory still comes back when the parent is filtered and
    # has to be in the parent's number too. Inactive children are simply never
    # serialized (the serializer renders `visible_subcategories`).
    child_ids_by_parent = categories.to_h { |c| [ c.id, c.subcategories.map(&:id) ] }
    all_ids = child_ids_by_parent.flat_map { |parent_id, child_ids| [ parent_id, *child_ids ] }

    # .except(:order): PostgreSQL rejects the ORDER BY column that `browsable`
    # carries (created_at) because it is neither grouped nor aggregated.
    direct = policy_scope(Listing.browsable)
               .not_hidden_for(current_user)
               .except(:order)
               .where(category_id: all_ids)
               .group(:category_id)
               .count

    counts = all_ids.index_with { |id| direct[id].to_i }
    child_ids_by_parent.each do |parent_id, child_ids|
      counts[parent_id] += child_ids.sum { |child_id| counts[child_id] }
    end
    counts
  end
end
