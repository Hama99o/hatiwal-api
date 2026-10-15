# Data: the Stays category tree on every database (production included), via
# Categories::StaysTree.apply! — idempotent; creates the Stays root and its own
# subcategories (kind "stay"). Moving Property › Guest Houses is the NEXT
# migration, kept separate (docs/STAYS_DESIGN.md §2.1, owner question).
# Reversible: down removes the Stays categories that hold no listing.
class SeedStaysCategories < ActiveRecord::Migration[8.1]
  def up
    Category.reset_column_information
    say "stays tree: #{Categories::StaysTree.apply!.inspect}"
  end

  def down
    Category.reset_column_information
    say "stays tree removed: #{Categories::StaysTree.remove!.inspect}"
  end
end
