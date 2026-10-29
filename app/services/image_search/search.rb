# Search by image (docs/IMAGE_SEARCH.md): ranks the listings of a scope by how
# much their photos look like the buyer's photo.
#
#   1. Image score: the best cosine similarity over each listing's photos
#      (every photo is indexed, so a listing whose 3rd photo matches is found).
#   2. Minimum score: below MIN_SCORE a listing is not shown at all. Without it
#      every search returns the whole market, best first, and a photo of
#      something we do not sell would list random items as "similar".
#   3. Same-category boost: the top VOTE_K matches vote for a top-level
#      category, weighted by their score; when one category holds at least
#      VOTE_SHARE of the votes, its listings get CATEGORY_BOOST. CLIP mixes up
#      look-alikes from different shelves (a hand holding a phone vs a hand
#      holding a jar, IMAGE_SEARCH_TEST §7); this pulls the shelf the photo most
#      probably shows to the front without hiding the rest.
#
# The numbers were tuned on the seed photos (docs/IMAGE_SEARCH.md §Tuning).
module ImageSearch
  class Search
    MIN_SCORE      = 0.62
    CATEGORY_BOOST = 0.03
    VOTE_K         = 10
    VOTE_SHARE     = 0.5
    MAX_RESULTS    = 60

    Result = Data.define(:listing_id, :score, :image_score)

    def self.call(vector, listings, index: RubyCosineIndex)
      new(vector, listings, index).results
    end

    def initialize(vector, listings, index)
      @vector = vector
      @listings = listings
      @index = index
    end

    # Results, best first, at most MAX_RESULTS.
    def results
      matches = @index.best_scores(@vector, @listings).select { |_id, (score, _cat)| score >= MIN_SCORE }
      return [] if matches.empty?

      roots = root_categories(matches.values.map(&:last).uniq)
      favourite = favourite_root(matches, roots)
      matches.map do |listing_id, (score, category_id)|
        boost = favourite && roots[category_id] == favourite ? CATEGORY_BOOST : 0.0
        Result.new(listing_id: listing_id, score: score + boost, image_score: score)
      end.sort_by { |r| [ -r.score, -r.listing_id ] }.first(MAX_RESULTS)
    end

    private

    # category id => its top-level category id.
    def root_categories(ids)
      Category.where(id: ids).pluck(:id, :parent_id).to_h { |id, parent_id| [ id, parent_id || id ] }
    end

    def favourite_root(matches, roots)
      votes = Hash.new(0.0)
      matches.values.max_by(VOTE_K) { |score, _cat| score }.each do |score, category_id|
        votes[roots[category_id]] += score
      end
      root, weight = votes.max_by { |_root, w| w }
      root if weight >= VOTE_SHARE * votes.values.sum
    end
  end
end
