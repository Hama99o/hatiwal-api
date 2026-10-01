# Sends a bulk email in batches (docs/EMAIL.md).
#
# Each run sends up to BATCH rows still `queued`, then re-enqueues itself after
# PAUSE — that is the rate limit. Every row is claimed atomically by
# AdminEmail#deliver! before its SMTP call, so a crashed, retried or duplicated
# run resumes where it stopped and never mails anyone twice.
#
# Before every row it checks: the campaign was not stopped, and the daily quota
# has room. At the cap it PAUSES (resumable) instead of letting Gmail reject
# mid-run. A row stuck in `sending` (a worker died mid-SMTP) is marked failed as
# "interrupted" — NOT re-sent, because it may already have gone.
class AdminBulkEmailJob < ApplicationJob
  queue_as :default

  BATCH = 10
  PAUSE = 1.minute
  STUCK_AFTER = 10.minutes

  def perform(bulk_email_id)
    bulk = AdminBulkEmail.find_by(id: bulk_email_id)
    return unless bulk&.sending?

    mark_interrupted(bulk)
    bulk.admin_emails.queued.order(:id).limit(BATCH).each do |row|
      return if bulk.reload.stopped?

      if Admin::MailQuota.remaining.zero?
        bulk.update!(status: :paused_daily_limit)
        return
      end
      row.deliver!
    end

    if bulk.remaining?
      self.class.set(wait: PAUSE).perform_later(bulk.id)
    else
      bulk.update!(status: :finished, finished_at: Time.current)
    end
  end

  private

  def mark_interrupted(bulk)
    bulk.admin_emails.sending.where(updated_at: ...STUCK_AFTER.ago)
        .update_all(status: AdminEmail.statuses[:failed],
                    error: "interrupted mid-send; not retried because it may already have been delivered")
  end
end
