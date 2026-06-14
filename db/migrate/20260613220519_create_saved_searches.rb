class CreateSavedSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_searches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :location
      t.references :category, foreign_key: true
      t.integer :price_min
      t.integer :price_max

      t.timestamps
    end

    add_index :saved_searches, [ :user_id, :created_at ], name: "index_saved_searches_user_recent"
  end
end
