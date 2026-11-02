# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1): the id the phone gives a message
# before it is sent. The sender's optimistic bubble and their other devices match
# the server's message on it. Null for every message from a 1.1.x app.
class AddClientUuidToMessages < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :messages, :client_uuid, :string, limit: 64
    add_index :messages, [ :user_id, :client_uuid ], unique: true, where: "client_uuid IS NOT NULL",
                                                     algorithm: :concurrently
  end
end
