# Data: the Stays category tree on every database (production included), via
# Categories::StaysTree — idempotent: creates what is missing, sets kind "stay"
# on the tree, and moves Property › Guest Houses under Stays (same row, its
# listings follow). Never deletes anything.
class SeedStaysCategories < ActiveRecord::Migration[8.1]
  def up
    Category.reset_column_information
    say "stays tree: #{Categories::StaysTree.apply!.inspect}"
  end

  def down
    # Leave the categories: listings may already use them.
  end
end
