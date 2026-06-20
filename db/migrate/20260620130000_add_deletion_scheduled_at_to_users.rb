class AddDeletionScheduledAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # 30-day deletion grace period. When a user requests deletion we set
    # deletion_scheduled_at (account becomes inaccessible to others + logged out,
    # but recoverable by logging back in). A daily job finalizes (anonymizes,
    # setting deleted_at) once the grace window has elapsed. Nil = not pending.
    add_column :users, :deletion_scheduled_at, :datetime
    add_index  :users, :deletion_scheduled_at
  end
end
