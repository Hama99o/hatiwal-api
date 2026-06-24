class AddIndexOnLastSignInAtToUsers < ActiveRecord::Migration[8.1]
  # users.last_sign_in_at is used in a WHERE filter by Listing.seller_active_within
  # (via joins(:user).where("users.last_sign_in_at >= ?", ...)) on the browse feed —
  # the app's busiest, guest-accessible endpoint.  An index prevents a sequential
  # scan of the users table on every filtered browse query.
  # Matches the convention set by the two preceding user-column migrations:
  # 20260620120000_add_deleted_at_to_users.rb and
  # 20260620130000_add_deletion_scheduled_at_to_users.rb.
  def change
    add_index :users, :last_sign_in_at
  end
end
