# IDEA-9 (1.2.1, hatiwal-mobile docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §4): a video sent in chunks.
# One row per upload; the bytes are appended to storage/uploads/<token>.part (the persistent storage volume,
# outside the web root, a server-made name). `key` is the client's UUID: a retry after a lost answer finds the
# same upload (unique per user). Swept after 24 h without a chunk (ResumableUploadSweepJob).
class CreateResumableUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :resumable_uploads do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token, null: false
      t.string :key, null: false, limit: 64
      t.integer :purpose, null: false
      t.bigint :size, null: false
      t.string :sha256, null: false, limit: 64
      t.bigint :offset, null: false, default: 0
      t.integer :status, null: false, default: 0
      # The blob a finalize attached: a second finalize (its answer was lost) answers the same.
      t.bigint :blob_id
      t.timestamps
    end
    add_index :resumable_uploads, :token, unique: true
    add_index :resumable_uploads, %i[user_id key], unique: true
    add_index :resumable_uploads, %i[status updated_at]
  end
end
