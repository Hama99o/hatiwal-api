module Admin
  # Read-only audit trail. Entries are created by moderation actions
  # (Admin::ApplicationController#log_admin_action), never edited.
  class AdminAuditLogsController < Admin::ApplicationController
  end
end
