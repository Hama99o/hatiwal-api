class AddDeletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # Account self-deletion (App Store 5.1.1(v) / Google Play). A deleted account
    # is anonymized (PII stripped) and blocked from login, but its messages are
    # retained (as "Deleted user") so other participants keep their history.
    # Nil = a live account.
    add_column :users, :deleted_at, :datetime
    add_index  :users, :deleted_at
  end
end
