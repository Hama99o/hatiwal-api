class AddReviewStatsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Denormalized aggregates over a user's VISIBLE reviews (as reviewee), so
    # listing/profile feeds never sum reviews per row. Recomputed only when a
    # review is revealed (see User#recompute_review_stats!).
    add_column :users, :avg_rating, :decimal, precision: 3, scale: 2
    add_column :users, :review_count, :integer, null: false, default: 0
    add_index :users, :avg_rating
  end
end
