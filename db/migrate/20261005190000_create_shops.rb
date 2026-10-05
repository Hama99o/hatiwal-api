# SHOP-1 — a business identity on top of a normal account
# (hatiwal-mobile/docs/SHOPS.md). One account stays one account: a shop belongs
# to a user, and `shop_members` exists from day one so phase 3 (team) adds rows,
# not a rewrite.
class CreateShops < ActiveRecord::Migration[8.1]
  def change
    create_table :shops do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :description
      t.references :category, null: false, foreign_key: true
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.string :province
      t.string :city
      t.string :address_line, null: false
      t.string :phone
      t.boolean :phone_public, null: false, default: false
      t.jsonb :hours, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.datetime :verified_at
      t.references :verified_by, foreign_key: { to_table: :admin_users }
      t.timestamps
    end
    # Admin filters (verified / waiting / suspended) and the province filter.
    add_index :shops, %i[status verified_at]
    add_index :shops, :province

    create_table :shop_members do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.references :invited_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :shop_members, %i[shop_id user_id], unique: true

    add_reference :listings, :shop, foreign_key: true
    add_reference :users, :active_shop, foreign_key: { to_table: :shops, on_delete: :nullify }
  end
end
