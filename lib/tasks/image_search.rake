# Search by image (docs/IMAGE_SEARCH.md).
namespace :image_search do
  desc "Embed every listing photo that has no vector of today's model (inline, batch by batch)"
  task backfill: :environment do
    abort "image model missing: run bin/fetch-image-model" unless ImageSearch::Embedder.available?

    after_id = 0
    total_embedded = total_failed = 0
    started = Time.current
    loop do
      embedded, failed, last_id = BackfillImageEmbeddingsJob.new.perform(after_id, enqueue_next: false)
      total_embedded += embedded
      total_failed += failed
      puts "image_search:backfill embedded=#{total_embedded} failed=#{total_failed} after_id=#{last_id || "done"}"
      break if last_id.nil?

      after_id = last_id
    end
    puts "image_search:backfill finished in #{(Time.current - started).round(1)} s (model #{ImageSearch::Embedder::MODEL_VERSION})"
  end

  desc "How many listing photos have a vector of today's model"
  task stats: :environment do
    photos = ActiveStorage::Attachment.where(record_type: Listing.name, name: "images").count
    current = ListingImageEmbedding.current_model.count
    puts "listing photos=#{photos} embedded(#{ImageSearch::Embedder::MODEL_VERSION})=#{current} " \
         "other model versions=#{ListingImageEmbedding.count - current}"
  end
end
