class Api::V1::CategoriesController < Api::V1::BaseController
  # Public reference data — guests browsing the feed need the category chips.
  skip_before_action :authenticate_user!, only: [ :index ]
  before_action :authenticate_optional!, only: [ :index ]

  def index
    authorize Category, :index?

    if params[:with_counts].present?
      # Category hub: compute active listing counts in a single GROUP BY query
      # (one SQL COUNT across all categories), then pass the hash to the serializer
      # so the :with_counts field block reads from it — zero extra queries per row.
      categories = Category.active.ordered.top_level.includes(:subcategories)
      category_ids = categories.map(&:id)
      # Strip the ORDER BY that .browsable includes — PostgreSQL rejects ORDER BY
      # columns that are not in GROUP BY or aggregate functions.
      counts_by_id = Listing.browsable
                            .except(:order)
                            .where(category_id: category_ids)
                            .group(:category_id)
                            .count
      render_blue_collection(CategorySerializer, categories, view: :with_counts,
                             options: { counts_by_id: counts_by_id })
    else
      categories = Category.active.ordered.top_level.includes(:subcategories)
      render_blue_collection(CategorySerializer, categories, view: :with_subcategories)
    end
  end
end
