class AddExpiresAtToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :expires_at, :datetime
    add_index :listings, :expires_at
  end
end
