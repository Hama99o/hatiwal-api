class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name_en, null: false
      t.string :name_ps, null: false
      t.string :name_fa, null: false
      t.string :slug, null: false
      t.string :icon
      t.integer :position, default: 0
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :categories, :slug, unique: true
    add_index :categories, :active
    add_index :categories, :position
  end
end
