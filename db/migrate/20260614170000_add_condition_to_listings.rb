class AddConditionToListings < ActiveRecord::Migration[8.1]
  def change
    # Item condition. Nullable — sellers may leave it unspecified.
    add_column :listings, :condition, :integer
    add_index :listings, :condition
  end
end
