class AddDeletedAtToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :buyer_deleted_at,  :datetime
    add_column :conversations, :seller_deleted_at, :datetime
    add_index  :conversations, :buyer_deleted_at
    add_index  :conversations, :seller_deleted_at

    # Conversations must survive listing deletion — nullify instead of cascade.
    # The serializer exposes listing_deleted: true when listing_id is nil.
    change_column_null :conversations, :listing_id, true
  end
end
