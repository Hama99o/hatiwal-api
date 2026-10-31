# IDEA-4: rebuilds the price-guide buckets every night (config/recurring.yml).
class PriceGuideRefreshJob < ApplicationJob
  queue_as :default

  def perform
    count = PriceGuides::Builder.call
    Rails.logger.info("price_guide_refresh buckets=#{count} published=#{PriceGuide.where(available: true).count}")
  end
end
