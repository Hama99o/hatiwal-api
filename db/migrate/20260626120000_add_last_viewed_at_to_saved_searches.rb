class AddLastViewedAtToSavedSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :saved_searches, :last_viewed_at, :datetime, default: nil
  end
end
