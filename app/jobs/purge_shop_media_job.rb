# SHOP-MEDIA, daily: delete the photos and video of every shop closed
# HasVideo::VIDEO_KEPT_FOR (30 days) ago or more. The shop row stays (closed
# shops are kept, Shop#close!); a shop reopened inside the window keeps them.
class PurgeShopMediaJob < ApplicationJob
  queue_as :default

  def perform
    Shop.media_purgeable.find_each(&:purge_media!)
  end
end
