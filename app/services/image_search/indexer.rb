# Search by image (docs/IMAGE_SEARCH.md): stores the embedding of one listing
# photo. Used by EmbedListingImageJob (a new photo) and
# BackfillImageEmbeddingsJob (photos from before the feature).
module ImageSearch
  class Indexer
    # Embeds `attachment` unless it already has a vector of today's model, and
    # stores its perceptual hashes (IDEA-5, ScamPhoto::Hasher) from the same
    # read. A row from before 1.2.1 only gets its hashes.
    # Returns true when a vector or hashes were written.
    def self.call(attachment)
      return false unless listing_photo?(attachment)

      existing = ListingImageEmbedding.current_model.find_by(attachment_id: attachment.id)
      return false if existing&.photo_hashes.present?

      bytes = attachment.blob.download
      if existing
        existing.update!(photo_hashes: photo_hashes(bytes))
        return true
      end

      vector = Embedder.embed(bytes)
      ListingImageEmbedding.upsert(
        { listing_id: attachment.record_id, attachment_id: attachment.id, model_version: Embedder::MODEL_VERSION,
          embedding: ListingImageEmbedding.pack(vector), photo_hashes: photo_hashes(bytes) },
        unique_by: %i[attachment_id model_version]
      )
      true
    rescue ActiveRecord::InvalidForeignKey
      # The photo (or its listing) was deleted while it was being embedded.
      false
    end

    # nil when the decoder cannot read it (the photo is still searchable).
    def self.photo_hashes(bytes)
      ScamPhoto::Hasher.hashes(bytes)
    rescue ScamPhoto::Hasher::InvalidImage
      nil
    end

    def self.listing_photo?(attachment)
      attachment.record_type == Listing.name && attachment.name == "images"
    end
  end
end
