class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :buyer,  null: false, foreign_key: { to_table: :users }
      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.integer :status, default: 0, null: false
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :conversations, [:listing_id, :buyer_id], unique: true
    add_index :conversations, :status
    add_index :conversations, :last_message_at
  end
end
