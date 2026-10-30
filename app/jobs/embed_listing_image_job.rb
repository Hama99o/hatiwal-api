# Search by image (docs/IMAGE_SEARCH.md): embeds one new listing photo.
# Enqueued after_create_commit of the attachment (config/initializers/image_search.rb).
class EmbedListingImageJob < ApplicationJob
  queue_as :image_embeddings
  # One embedding job at a time across the whole app (they share the key): the
  # others wait as blocked jobs WITHOUT holding a worker thread, so a burst of
  # new photos or a backfill never delays chat pushes and the other jobs that
  # share the worker's 3 threads.
  limits_concurrency to: 1, key: ->(*) { "image_embeddings" }, duration: 10.minutes

  # The file can still be on its way to storage when the job first runs.
  retry_on ActiveStorage::FileNotFoundError, wait: 30.seconds, attempts: 5
  # A photo the decoder cannot read will not get better by retrying, and a
  # server without the model has search by image switched off: log and stop.
  discard_on ImageSearch::Embedder::InvalidImage, ImageSearch::Embedder::Unavailable do |job, error|
    Rails.logger.warn("[image_search] attachment #{job.arguments.first} not embedded: #{error.class}: #{error.message}")
  end

  def perform(attachment_id)
    attachment = ActiveStorage::Attachment.find_by(id: attachment_id)
    return if attachment.nil?

    # IDEA-5: a photo with new hashes is matched against other accounts' photos.
    ScamPhotoMatchJob.perform_later(attachment.record_id) if ImageSearch::Indexer.call(attachment)
  end
end
