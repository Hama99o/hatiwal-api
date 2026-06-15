class CreateListingPriceHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_price_histories do |t|
      t.references :listing, null: false, foreign_key: true, index: true
      t.decimal :old_price, null: false, precision: 12, scale: 2
      t.decimal :new_price, null: false, precision: 12, scale: 2
      t.string :currency, null: false, default: "AFN"
      t.datetime :changed_at, null: false

      t.timestamps
    end

    add_index :listing_price_histories, :changed_at
  end
end
