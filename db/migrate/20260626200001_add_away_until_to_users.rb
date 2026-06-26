class AddAwayUntilToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :away_until, :datetime
  end
end
