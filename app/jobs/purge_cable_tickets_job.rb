# Every 10 minutes: forget the cable tickets never used (CableTicket::TTL is a
# minute; a used one is already gone).
class PurgeCableTicketsJob < ApplicationJob
  queue_as :default

  def perform
    CableTicket.expired.in_batches(of: 1000).delete_all
  end
end
