class AddRemovedToListings < ActiveRecord::Migration[8.1]
  def change
    # Admin take-down (soft remove): a removed listing is hidden from the public
    # feed and detail page but kept for the record. Nil = visible.
    add_column :listings, :removed_at, :datetime
    add_column :listings, :removed_reason, :string
    add_index  :listings, :removed_at
  end
end
