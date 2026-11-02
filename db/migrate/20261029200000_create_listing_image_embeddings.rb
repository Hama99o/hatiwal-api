# Search by image (docs/IMAGE_SEARCH.md): one row per listing photo, holding its
# CLIP vector. No pgvector in 1.2.0 (production runs plain postgres:16, and
# changing the DB image means a DB restart), so the vector is 512 float32s
# packed into a bytea and the cosine search runs in Ruby
# (ImageSearch::RubyCosineIndex). A later move to pgvector + neighbor only adds
# a `vector(512)` column filled from this one.
#
# Both foreign keys cascade: a removed photo or a deleted listing takes its
# rows with it, with no callback to forget.
class CreateListingImageEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_image_embeddings do |t|
      t.references :listing, null: false, foreign_key: { on_delete: :cascade }
      t.references :attachment, null: false, index: false,
                                foreign_key: { to_table: :active_storage_attachments, on_delete: :cascade }
      t.string :model_version, null: false, limit: 64
      t.binary :embedding, null: false
      t.timestamps
    end
    add_index :listing_image_embeddings, %i[attachment_id model_version], unique: true,
                                         name: "index_listing_image_embeddings_on_attachment_and_model"
  end
end
