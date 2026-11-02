# VID, daily: delete the video (and its poster) of every listing that has been
# sold, expired or deleted for Listing::VIDEO_KEPT_FOR (30 days) or more.
# The photos and the listing stay — only the heavy file goes.
class PurgeListingVideosJob < ApplicationJob
  queue_as :default

  def perform
    Listing.video_purgeable.find_each(&:purge_video!)
  end
end
