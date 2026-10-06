# SHOP-3 — the team (hatiwal-mobile/docs/SHOPS.md, "Phase 3 — the team").
# shop_members.role already has owner / manager / staff (phase 1): no change.
class ShopPhaseThree < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_invites do |t|
      t.references :shop, null: false, foreign_key: { on_delete: :cascade }
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :token, null: false
      # An email invite binds to that CONFIRMED email; null = a plain link.
      t.string :email
      t.integer :role, null: false, default: 2 # staff (ShopMember.roles)
      t.integer :status, null: false, default: 0
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :decided_at
      t.timestamps
    end
    add_index :shop_invites, :token, unique: true
    add_index :shop_invites, %i[shop_id status]
    add_index :shop_invites, :email

    create_table :shop_audit_events do |t|
      t.references :shop, null: false, foreign_key: { on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :target_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :action, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :shop_audit_events, %i[shop_id created_at]

    # The member who recorded a shop sale; the sale's seller is the shop owner.
    add_reference :transactions, :recorded_by, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
