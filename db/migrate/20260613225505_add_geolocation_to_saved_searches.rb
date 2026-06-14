class AddGeolocationToSavedSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :saved_searches, :latitude, :float
    add_column :saved_searches, :longitude, :float
    add_column :saved_searches, :radius, :integer
  end
end
