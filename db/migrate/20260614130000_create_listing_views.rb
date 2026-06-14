class CreateListingViews < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_views do |t|
      t.references :user, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.datetime :last_viewed_at, null: false

      t.timestamps
    end

    add_index :listing_views, [ :user_id, :listing_id ], unique: true
  end
end
