class AddBlockReasonToUsers < ActiveRecord::Migration[8.1]
  def change
    # Admin-entered explanation shown to a suspended/banned user so they know
    # why they were blocked. Nil while the account is active.
    add_column :users, :block_reason, :string
  end
end
