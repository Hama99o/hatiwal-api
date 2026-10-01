# Sends one one-to-one AdminEmail (AdminEmail#deliver! claims, sends, records).
# Not retried automatically: a retry after a send that actually went out would
# mail the user twice. A failure stays visible on the row.
class AdminEmailDeliveryJob < ApplicationJob
  queue_as :default

  def perform(admin_email_id)
    AdminEmail.find_by(id: admin_email_id)&.deliver!
  end
end
