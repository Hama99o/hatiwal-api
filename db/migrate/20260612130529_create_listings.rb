class CreateListings < ActiveRecord::Migration[8.1]
  def change
    create_table :listings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      t.string  :title, null: false
      t.text    :description
      t.decimal :price, precision: 12, scale: 2, null: false
      t.string  :currency, default: "AFN", null: false
      t.integer :status, default: 0, null: false
      t.string  :location
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.integer :views_count, default: 0, null: false
      t.datetime :published_at
      t.datetime :reserved_at
      t.datetime :sold_at

      t.timestamps
    end

    add_index :listings, :status
    add_index :listings, :created_at
    add_index :listings, :price
    add_index :listings, [:status, :created_at]
  end
end
