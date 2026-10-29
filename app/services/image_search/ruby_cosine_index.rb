# Search by image (docs/IMAGE_SEARCH.md): the nearest-photo lookup, done in Ruby.
#
# 1.2.0 has no pgvector (production runs plain postgres:16), so this reads the
# vectors of the listings in `listings` and scores each one with a dot product
# (the vectors are unit-length, so that IS the cosine similarity). It is exact,
# not approximate. Measured on 5 000 photos: see docs/IMAGE_SEARCH.md §Speed.
#
# This class is the seam. A pgvector version only has to answer the same
# question — { listing_id => [best score, category_id] } for the photos of
# `listings` — e.g. with neighbor's `nearest_neighbors(:embedding, vector,
# distance: "cosine")` grouped by listing; ImageSearch::Search stays as it is.
module ImageSearch
  class RubyCosineIndex
    # vector: unit-length Array of floats. listings: an ActiveRecord scope.
    # Returns { listing_id => [best cosine over its photos, category_id] }.
    def self.best_scores(vector, listings)
      dims = vector.size
      best = {}
      rows = ListingImageEmbedding.current_model
                                  .joins(:listing)
                                  .where(listing_id: listings.unscope(:order, :includes, :select).select(:id))
                                  .pluck(:listing_id, "listings.category_id", :embedding)
      rows.each do |listing_id, category_id, bytes|
        other = ListingImageEmbedding.unpack(bytes)
        score = 0.0
        i = 0
        while i < dims
          score += vector[i] * other[i]
          i += 1
        end
        current = best[listing_id]
        best[listing_id] = [ score, category_id ] if current.nil? || score > current[0]
      end
      best
    end
  end
end
