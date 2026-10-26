# OFFLINE phase 2a (docs/OFFLINE_MODE.md §7.2, §10.2): when, and by whom, each
# field of a listing was last changed — what an edit conflict tells the seller
# ("Price changed elsewhere: 480, by Ahmad at 14:02"). {field => {at, by}}.
class AddFieldEditsToListings < ActiveRecord::Migration[8.0]
  def change
    add_column :listings, :field_edits, :jsonb, null: false, default: {}
  end
end
