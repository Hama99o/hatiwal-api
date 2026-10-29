# Search by image (docs/IMAGE_SEARCH.md): the CLIP vector of ONE listing photo.
#
# The vector is stored as DIMENSIONS little-endian float32s in a bytea (2 KB a
# row), already unit-length, so a cosine similarity is a plain dot product.
# Rows of another model_version are never compared with today's vectors.
class ListingImageEmbedding < ApplicationRecord
  PACK_FORMAT = "e*".freeze

  belongs_to :listing, class_name: Listing.name
  belongs_to :attachment, class_name: ActiveStorage::Attachment.name

  validates :model_version, presence: true
  validates :embedding, presence: true
  validate :embedding_has_the_model_size

  scope :current_model, -> { where(model_version: ImageSearch::Embedder::MODEL_VERSION) }

  def self.pack(vector) = vector.pack(PACK_FORMAT)
  def self.unpack(bytes) = bytes.unpack(PACK_FORMAT)

  def vector = self.class.unpack(embedding)

  def vector=(values)
    self.embedding = self.class.pack(values)
  end

  private

  def embedding_has_the_model_size
    return if embedding.nil? || embedding.bytesize == ImageSearch::Embedder::DIMENSIONS * 4

    errors.add(:embedding, :invalid)
  end
end
