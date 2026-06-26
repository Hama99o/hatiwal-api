class AddArchivedAtToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :buyer_archived_at,  :datetime
    add_column :conversations, :seller_archived_at, :datetime
  end
end
