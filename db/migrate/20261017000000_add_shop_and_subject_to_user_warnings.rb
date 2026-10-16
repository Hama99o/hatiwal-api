# frozen_string_literal: true

# Business answers for what it sells (owner, 2026-10-16): a warning can now be
# issued to a SHOP as well as a user (a shop listing taken down with a warning
# strikes BOTH the poster and the shop). Additive and 1.1.6-safe: existing rows
# keep user_id and a nil shop_id.
#   shop_id      — the shop a shop-warning belongs to (nil for a user warning)
#   posted_by_id — the team member who posted the taken-down listing (shop warnings)
#   listing_id   — the listing the warning is about, for latest_warning.listing_title
# user_id becomes nullable so a shop warning needs no user.
class AddShopAndSubjectToUserWarnings < ActiveRecord::Migration[8.1]
  def change
    change_column_null :user_warnings, :user_id, true
    add_reference :user_warnings, :shop, null: true, foreign_key: true
    add_reference :user_warnings, :posted_by, null: true, foreign_key: { to_table: :users }
    add_reference :user_warnings, :listing, null: true, foreign_key: true
    add_index :user_warnings, [ :shop_id, :expires_at ]
  end
end
