# Sends one AdminEmail and records the outcome on it, so the admin sees "sent"
# or "failed: <reason>" in the user's email history instead of wondering.
#
# Not retried automatically: a retry after a send that actually went out would
# mail the user twice, and email can't be unsent. A failure stays visible.
class AdminEmailDeliveryJob < ApplicationJob
  queue_as :default

  def perform(admin_email_id)
    admin_email = AdminEmail.find_by(id: admin_email_id)
    return unless admin_email&.queued?

    AdminMessageMailer.direct(admin_email).deliver_now
    admin_email.update!(status: :sent, sent_at: Time.current, error: nil)
  rescue StandardError => e
    admin_email&.update_columns(status: AdminEmail.statuses[:failed], error: "#{e.class}: #{e.message}".truncate(500))
  end
end
