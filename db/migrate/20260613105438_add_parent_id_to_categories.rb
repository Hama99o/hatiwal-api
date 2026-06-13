class AddParentIdToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :parent_id, :bigint, null: true
    add_index  :categories, :parent_id
    add_foreign_key :categories, :categories, column: :parent_id, on_delete: :restrict
  end
end
