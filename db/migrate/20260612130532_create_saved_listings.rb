class CreateSavedListings < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_listings do |t|
      t.references :user,    null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true

      t.timestamps
    end

    add_index :saved_listings, [ :user_id, :listing_id ], unique: true
  end
end
