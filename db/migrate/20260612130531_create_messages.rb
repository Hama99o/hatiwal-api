class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :kind, default: 0, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :messages, :created_at
    add_index :messages, :read_at
  end
end
