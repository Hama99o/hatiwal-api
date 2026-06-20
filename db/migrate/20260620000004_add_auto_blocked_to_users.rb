class AddAutoBlockedToUsers < ActiveRecord::Migration[8.1]
  def change
    # True when the account was suspended automatically by the strike system
    # (vs. a manual admin block). Only auto-blocks are lifted when warnings decay.
    add_column :users, :auto_blocked, :boolean, null: false, default: false
  end
end
