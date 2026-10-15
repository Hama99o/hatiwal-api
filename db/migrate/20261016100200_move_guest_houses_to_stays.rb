# Data, option A of docs/STAYS_DESIGN.md §2.1 (the default until the owner
# answers): Property › Guest Houses moves under Stays — the same row, so its
# listings follow. Option B (keep it under Property) = delete this migration
# and add a new stays subcategory to StaysTree::CHILDREN. Reversible.
class MoveGuestHousesToStays < ActiveRecord::Migration[8.1]
  def up
    Category.reset_column_information
    say "guest houses: #{Categories::StaysTree.move_guest_houses!.inspect}"
  end

  def down
    Category.reset_column_information
    say "guest houses: #{Categories::StaysTree.restore_guest_houses!.inspect}"
  end
end
