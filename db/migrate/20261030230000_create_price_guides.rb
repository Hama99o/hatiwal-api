# IDEA-4 (docs/PRICE_GUIDE.md): one row per subcategory + currency, rebuilt
# nightly by PriceGuideRefreshJob. Aggregates only — no sale, buyer or seller
# is stored here. low/high are set only when the bucket is `available`.
class CreatePriceGuides < ActiveRecord::Migration[8.1]
  def change
    create_table :price_guides do |t|
      t.references :category, null: false, foreign_key: { on_delete: :cascade }
      t.string :currency, null: false
      t.integer :sales_count, null: false, default: 0
      t.integer :sellers_count, null: false, default: 0
      t.decimal :low, precision: 12, scale: 2
      t.decimal :high, precision: 12, scale: 2
      t.boolean :available, null: false, default: false
      t.datetime :refreshed_at, null: false
      t.timestamps
    end
    add_index :price_guides, %i[category_id currency], unique: true
  end
end
