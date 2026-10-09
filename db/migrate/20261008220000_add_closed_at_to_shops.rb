# Side branch closed-shop-face (2026-10-08): WHEN a shop closed, so the messages
# its team wrote as the shop before the closure keep the shop's face, and only
# what the owner writes after it is personal. Shops closed before this column
# take their last update as the closing time (close! is their last write).
class AddClosedAtToShops < ActiveRecord::Migration[8.1]
  def up
    add_column :shops, :closed_at, :datetime
    execute "UPDATE shops SET closed_at = updated_at WHERE status = 3"
  end

  def down
    remove_column :shops, :closed_at
  end
end
