# Sell with a photo (docs/SELL_WITH_PHOTO.md §4).
namespace :category_suggestion do
  desc "Build the category vectors into the shared cache once, so the first seller after a deploy does not wait"
  task warm: :environment do
    abort "text model missing: run bin/fetch-image-model" unless ImageSearch::TextEmbedder.available?

    started = Time.current
    count = CategorySuggestion.warm!
    puts "category_suggestion:warm #{count} categories ready in #{(Time.current - started).round(1)} s " \
         "(model #{ImageSearch::Embedder::MODEL_VERSION})"
  end
end
