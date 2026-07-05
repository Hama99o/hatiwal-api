class AddPriceAtSaveToSavedListings < ActiveRecord::Migration[8.1]
  def up
    add_column :saved_listings, :price_at_save, :decimal, precision: 12, scale: 2

    # Backfill existing rows with the listing's current price so the
    # "price dropped" comparison is meaningful (no drop) for saves that
    # predate this column instead of showing a false badge for everyone.
    execute <<~SQL.squish
      UPDATE saved_listings
      SET price_at_save = listings.price
      FROM listings
      WHERE listings.id = saved_listings.listing_id
        AND saved_listings.price_at_save IS NULL
    SQL

    change_column_null :saved_listings, :price_at_save, false
  end

  def down
    remove_column :saved_listings, :price_at_save
  end
end
