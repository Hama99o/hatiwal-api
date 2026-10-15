# Stays (docs/STAYS_DESIGN.md): a category KIND clients switch on, a listing's
# price unit ("per night") and its typed details (guests, beds, amenities…).
# All three are additive with safe defaults: every existing row keeps meaning
# exactly what it meant ("item", a total price, no details).
class AddStaysColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :kind, :string, null: false, default: "item"
    add_column :listings, :price_unit, :string
    add_column :listings, :details, :jsonb, null: false, default: {}
    add_index :listings, :details, using: :gin
  end
end
