class AddNegotiableToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :negotiable, :boolean, default: true, null: false
  end
end
