class AddIndexOnViewsCountToListings < ActiveRecord::Migration[8.1]
  def change
    # Support the most_viewed sort (ORDER BY views_count DESC) cheaply.
    # The composite index mirrors the existing [:status, :created_at] index
    # so the planner can satisfy the common browsable + most_viewed query
    # (WHERE status = 1 ORDER BY views_count DESC) with an index-only scan.
    add_index :listings, %i[status views_count], name: "index_listings_on_status_and_views_count"
  end
end
