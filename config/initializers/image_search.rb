# Search by image (docs/IMAGE_SEARCH.md).
require "vips"

# Every new LISTING photo gets its embedding. Only listing photos: avatars,
# chat photos, shop media and verification files are never embedded.
# A removed photo needs no hook: its rows go with it (ON DELETE CASCADE on
# listing_image_embeddings.attachment_id).
ActiveSupport.on_load(:active_storage_attachment) do
  after_create_commit :enqueue_image_embedding, if: -> { record_type == "Listing" && name == "images" }

  def enqueue_image_embedding
    return unless ImageSearch.enabled?

    EmbedListingImageJob.perform_later(id)
  end
end
