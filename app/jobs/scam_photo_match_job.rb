# IDEA-5 scam photo detection (1.2.1): matches one listing's photos against other accounts' live
# listings (ScamPhoto::Matcher). Queued after a photo is indexed (EmbedListingImageJob) and when a
# listing goes live (Listing#enqueue_scam_photo_match): a draft's photos are indexed before it is
# published, and only live listings are matched.
class ScamPhotoMatchJob < ApplicationJob
  queue_as :image_embeddings
  # Shares the embedding jobs' key: one at a time, after the photo it needs.
  limits_concurrency to: 1, key: ->(*) { "image_embeddings" }, duration: 10.minutes

  def perform(listing_id)
    listing = Listing.find_by(id: listing_id)
    return if listing.nil?

    ScamPhoto::Matcher.call(listing)
  end
end
