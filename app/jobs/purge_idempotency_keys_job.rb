# OFFLINE phase 2a, daily: forget idempotency keys older than
# IdempotencyKey::KEPT_FOR (30 days) — a retry that old is not a retry.
class PurgeIdempotencyKeysJob < ApplicationJob
  queue_as :default

  def perform
    IdempotencyKey.expired.in_batches(of: 1000).delete_all
  end
end
