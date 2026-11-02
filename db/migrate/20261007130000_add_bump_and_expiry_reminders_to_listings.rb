# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): expiry must never
# hurt the seller.
#
# - `bumped_at`: where a listing sits in the newest-first feed. It used to be
#   `created_at`, which nothing can move; now an edit + relaunch may move a
#   listing back to the top, at most once a week (Listing::BUMP_INTERVAL). A
#   plain Renew never touches it. Backfilled from `created_at`, so the feed
#   order is exactly what it was the moment this runs.
# - `expiry_reminder_week_for` / `expiry_reminder_day_for`: the `expires_at` a
#   7-day / 1-day reminder was sent FOR. A renew moves `expires_at`, which
#   re-arms both: one reminder of each per listing per expiry.
class AddBumpAndExpiryRemindersToListings < ActiveRecord::Migration[8.1]
  def up
    add_column :listings, :bumped_at, :datetime, if_not_exists: true
    execute "UPDATE listings SET bumped_at = created_at WHERE bumped_at IS NULL"
    change_column_default :listings, :bumped_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
    change_column_null :listings, :bumped_at, false
    add_index :listings, :bumped_at, if_not_exists: true

    add_column :listings, :expiry_reminder_week_for, :datetime, if_not_exists: true
    add_column :listings, :expiry_reminder_day_for, :datetime, if_not_exists: true
  end

  def down
    remove_column :listings, :expiry_reminder_day_for, if_exists: true
    remove_column :listings, :expiry_reminder_week_for, if_exists: true
    remove_index :listings, :bumped_at, if_exists: true
    remove_column :listings, :bumped_at, if_exists: true
  end
end
