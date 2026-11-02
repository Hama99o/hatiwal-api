# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1): one row per (user, Idempotency-Key).
# The unique index is what makes two concurrent requests with the same key safe:
# the second INSERT fails and the request is answered from (or refused by) the first.
class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :key, null: false, limit: 64
      t.string :request_fingerprint, null: false, limit: 64
      t.integer :status, null: false, default: 0
      t.integer :response_code
      t.jsonb :response_body
      t.timestamps
    end
    add_index :idempotency_keys, %i[user_id key], unique: true
    add_index :idempotency_keys, :created_at
  end
end
