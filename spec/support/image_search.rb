# Search by image (docs/IMAGE_SEARCH.md) is off in the test environment
# (config.x.image_search_enabled = false). Tag a spec `:image_search` to switch
# it on; its embedder is stubbed unless the spec is also tagged
# `:image_model`, which runs the real CLIP model and is skipped (with a reason)
# when bin/fetch-image-model has not been run on this machine.
module ImageSearchHelpers
  # A unit vector of the model's size pointing mostly along `axis`, with a
  # `mix` share of `other`: cosine(fake_vector(0), fake_vector(0, other: 1, mix: m))
  # is predictable, so ranking specs can state exact expectations.
  def fake_vector(axis, other: nil, mix: 0.0)
    v = Array.new(ImageSearch::Embedder::DIMENSIONS, 0.0)
    v[axis] = Math.sqrt(1.0 - mix)
    v[other] = Math.sqrt(mix) if other
    v
  end

  def embed_photo!(listing, vector, attachment: listing.images.attachments.first)
    ListingImageEmbedding.create!(listing: listing, attachment: attachment,
                                  model_version: ImageSearch::Embedder::MODEL_VERSION, vector: vector)
  end
end

RSpec.configure do |config|
  config.include ImageSearchHelpers

  config.around(:each, :image_search) do |example|
    Rails.configuration.x.image_search_enabled = true
    example.run
  ensure
    Rails.configuration.x.image_search_enabled = false
  end

  config.before(:each, :image_search) do |example|
    if example.metadata[:image_model]
      skip("image model not fetched (bin/fetch-image-model)") unless ImageSearch::Embedder.available?
    else
      allow(ImageSearch::Embedder).to receive(:available?).and_return(true)
    end
  end
end
