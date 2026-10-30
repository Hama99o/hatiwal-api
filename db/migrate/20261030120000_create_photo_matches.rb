# IDEA-5 scam photo detection (1.2.1, hatiwal-mobile docs/design/SCAM_PHOTO.md).
#
# photo_hashes: the 9 perceptual hashes of the photo (ScamPhoto::Hasher: 7
# stored transforms + 2 query views), written by the image-search indexer next
# to the CLIP vector it already stores. NULL until hashed (rows from before 1.2.1
# get theirs from `bin/rails scam_photo:backfill`).
#
# photo_matches: one row per pair of listings of DIFFERENT accounts that share a
# photo — `listing` is the newer one (it carries the Flag), `matched_listing` the
# older, likely original. Dismissed pairs stay, so they are never flagged again.
# Photos may go (nullify: the scores stay as evidence); a deleted listing takes
# its pairs with it.
class CreatePhotoMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :listing_image_embeddings, :photo_hashes, :bigint, array: true

    create_table :photo_matches do |t|
      t.references :listing, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :matched_listing, null: false, foreign_key: { to_table: :listings, on_delete: :cascade }
      t.references :attachment, foreign_key: { to_table: :active_storage_attachments, on_delete: :nullify }
      t.references :matched_attachment, foreign_key: { to_table: :active_storage_attachments, on_delete: :nullify }
      t.references :flag, foreign_key: { on_delete: :nullify }
      t.float :cosine, null: false
      t.integer :hash_distance, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :photo_matches, %i[listing_id matched_listing_id], unique: true
  end
end
