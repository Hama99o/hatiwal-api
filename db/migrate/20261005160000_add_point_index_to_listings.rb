# LOC-1 review — nearest-first is the DEFAULT Bazaar order now, and it narrows
# to a lat/lng box before sorting (Listing.nearest_window_km). This is the index
# that box scans. Partial: listings without a point never enter the box.
class AddPointIndexToListings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :listings, %i[latitude longitude],
              where: "latitude IS NOT NULL AND longitude IS NOT NULL AND removed_at IS NULL",
              name: "index_listings_on_point_browsable",
              algorithm: :concurrently
  end
end
