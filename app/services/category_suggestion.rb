# Sell with a photo (docs/SELL_WITH_PHOTO.md): which category does the first
# photo of a new listing show? Zero-shot CLIP:
#
#   1. Each suggestible category has English prompts (config/sell_photo/
#      prompts.yml); their text vectors are averaged into one category vector.
#   2. The photo's vector (ImageSearch::Embedder) is compared with every
#      category vector; cosine x LOGIT_SCALE, then a softmax over categories.
#   3. The best category is suggested only at MIN_CONFIDENCE or more.
#
# MIN_CONFIDENCE was chosen on 170 held-out photos: precision 0.94, 58% of
# photos get a suggestion (docs/SELL_WITH_PHOTO.md §Measured). The apps never
# apply it by themselves: the seller taps it, or not.
module CategorySuggestion
  MIN_CONFIDENCE = 0.40
  # CLIP's own learned temperature (logit_scale = 100 in this model).
  LOGIT_SCALE = 100.0
  PROMPTS_PATH = Rails.root.join("config/sell_photo/prompts.yml")
  # What the seller did with a suggestion (POST .../category_suggestion/outcome).
  OUTCOMES = %w[accepted dismissed replaced].freeze

  Result = Data.define(:category_id, :parent_id, :confidence)

  LOCK = Mutex.new

  class << self
    # On when both halves of the model are on this server (search by image's
    # own switch included), unless CATEGORY_SUGGESTION_ENABLED=0.
    def enabled?
      return false if ENV["CATEGORY_SUGGESTION_ENABLED"] == "0"

      ImageSearch.enabled? && ImageSearch::TextEmbedder.available?
    end

    # photo vector (unit length) -> Result, or nil when not sure.
    #
    # The softmax runs over EVERY slug of the prompts file, whatever the
    # database holds: a switched-off category still takes its share (a phone
    # photo stays "phones" and is then not suggested), instead of the last
    # categories left splitting 100% between them.
    def call(vector)
      logits = slug_vectors.transform_values { |slug_vector| LOGIT_SCALE * dot(vector, slug_vector) }
      top = logits.values.max
      weights = logits.transform_values { |logit| Math.exp(logit - top) }
      slug, weight = weights.max_by { |_slug, w| w }
      confidence = weight / weights.values.sum
      return if confidence < MIN_CONFIDENCE

      category = Category.active.find_by(slug: slug)
      return unless category

      Result.new(category_id: category.id, parent_id: category.parent_id, confidence: confidence.round(3))
    end

    # slug => [English phrases]. Only these slugs can ever be suggested.
    def prompts
      @prompts ||= YAML.safe_load_file(PROMPTS_PATH).transform_values { |phrases| Array(phrases).map(&:to_s) }
    end

    # For specs: forget the per-process vectors.
    def reset!
      LOCK.synchronize { @slug_vectors = @prompts = nil }
    end

    private

    # { slug => unit vector }: the mean of the slug's phrase vectors. Depends
    # only on the model and the prompts file, so it is built once per process,
    # and once per release in Rails.cache (embedding the phrases takes ~6 s).
    def slug_vectors
      LOCK.synchronize do
        @slug_vectors ||= Rails.cache.fetch(cache_key) { build }
      end
    end

    def build
      vectors = ImageSearch::TextEmbedder.embed_all(prompts.values.flatten).each
      prompts.transform_values do |phrases|
        ImageSearch::Embedder.normalize(phrases.map { vectors.next }.transpose.map(&:sum))
      end
    end

    def cache_key
      "category_suggestion/#{ImageSearch::Embedder::MODEL_VERSION}/#{Digest::SHA256.file(PROMPTS_PATH).hexdigest}"
    end

    def dot(a, b)
      sum = 0.0
      a.each_index { |i| sum += a[i] * b[i] }
      sum
    end
  end
end
