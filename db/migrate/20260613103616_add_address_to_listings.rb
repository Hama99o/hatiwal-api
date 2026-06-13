class AddAddressToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :address, :string
  end
end
