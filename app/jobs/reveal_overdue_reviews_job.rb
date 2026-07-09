# Daily sweep that reveals reviews whose counterparty never responded within
# Review::REVEAL_WINDOW — so an unresponsive party can't block the other's
# review forever. Scheduled in config/recurring.yml.
class RevealOverdueReviewsJob < ApplicationJob
  queue_as :default

  def perform
    Review.overdue_hidden.find_each(&:reveal_now!)
  end
end
