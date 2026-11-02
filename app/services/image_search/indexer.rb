# Search by image (docs/IMAGE_SEARCH.md): stores the embedding of one listing
# photo. Used by EmbedListingImageJob (a new photo) and
# BackfillImageEmbeddingsJob (photos from before the feature).
module ImageSearch
  class Indexer
    # Embeds `attachment` unless it already has a vector of today's model.
    # Returns true when a vector was written.
    def self.call(attachment)
      return false unless listing_photo?(attachment)
      return false if ListingImageEmbedding.current_model.exists?(attachment_id: attachment.id)

      vector = Embedder.embed(attachment.blob.download)
      ListingImageEmbedding.upsert(
        { listing_id: attachment.record_id, attachment_id: attachment.id,
          model_version: Embedder::MODEL_VERSION, embedding: ListingImageEmbedding.pack(vector) },
        unique_by: %i[attachment_id model_version]
      )
      true
    rescue ActiveRecord::InvalidForeignKey
      # The photo (or its listing) was deleted while it was being embedded.
      false
    end

    def self.listing_photo?(attachment)
      attachment.record_type == Listing.name && attachment.name == "images"
    end
  end
end
