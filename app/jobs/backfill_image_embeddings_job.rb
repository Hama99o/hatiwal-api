# Search by image (docs/IMAGE_SEARCH.md): embeds the listing photos that have
# no vector of today's model — every photo from before the feature, and all of
# them again after a MODEL_VERSION change.
#
# One batch per run, then it enqueues the next batch after the last attachment
# id it saw, so no job runs for long and a photo that fails (an unreadable file)
# is skipped instead of being picked up again forever.
#
#   bin/rails image_search:backfill            # runs every batch inline
#   BackfillImageEmbeddingsJob.perform_later   # in the background
class BackfillImageEmbeddingsJob < ApplicationJob
  queue_as :image_embeddings
  # One embedding job at a time across the whole app (they share the key): the
  # others wait as blocked jobs WITHOUT holding a worker thread, so a burst of
  # new photos or a backfill never delays chat pushes and the other jobs that
  # share the worker's 3 threads.
  limits_concurrency to: 1, key: ->(*) { "image_embeddings" }, duration: 10.minutes

  BATCH_SIZE = 100

  discard_on ImageSearch::Embedder::Unavailable do |_job, error|
    Rails.logger.warn("[image_search] backfill stopped: #{error.message}")
  end

  # Returns [embedded, failed, last attachment id or nil when done].
  def perform(after_id = 0, enqueue_next: true)
    batch = self.class.pending(after_id).limit(BATCH_SIZE).to_a
    embedded = failed = 0
    batch.each do |attachment|
      embedded += 1 if ImageSearch::Indexer.call(attachment)
    rescue ImageSearch::Embedder::InvalidImage, ActiveStorage::FileNotFoundError => e
      failed += 1
      Rails.logger.warn("[image_search] backfill skipped attachment #{attachment.id}: #{e.class}: #{e.message}")
    end
    last_id = batch.size == BATCH_SIZE ? batch.last.id : nil
    self.class.perform_later(last_id) if last_id && enqueue_next
    [ embedded, failed, last_id ]
  end

  def self.pending(after_id = 0)
    ActiveStorage::Attachment
      .where(record_type: Listing.name, name: "images")
      .where("active_storage_attachments.id > ?", after_id)
      .where.not(id: ListingImageEmbedding.current_model.select(:attachment_id))
      .includes(:blob)
      .order(:id)
  end
end
