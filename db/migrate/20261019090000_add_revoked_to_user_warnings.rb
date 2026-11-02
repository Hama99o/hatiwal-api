# An admin can cancel a warning given by mistake or overturned on appeal
# (owner, 2026-10-19). The row is kept for the history; it just stops counting.
class AddRevokedToUserWarnings < ActiveRecord::Migration[8.1]
  def change
    add_column :user_warnings, :revoked_at, :datetime
    add_column :user_warnings, :revoke_reason, :string
    add_reference :user_warnings, :revoked_by, foreign_key: { to_table: :admin_users }, index: false
  end
end
