# Base controller for every Administrate screen.
#
# Security posture (this surface can edit ANY user / listing / category, so it
# is locked down deliberately):
#   * authenticate_admin_user!  — no page is reachable without a valid admin
#     session. AdminUser is a separate Devise model from the mobile User, so a
#     marketplace API token can never reach here.
#   * protect_from_forgery       — the host app runs `config.api_only = true`,
#     which disables Rails' default CSRF protection. Admin pages submit HTML
#     forms backed by a browser session, so we re-enable it explicitly.
module Admin
  class ApplicationController < Administrate::ApplicationController
    protect_from_forgery with: :exception

    before_action :authenticate_admin_user!

    private

    # Record a moderation action for accountability. Failures here must never
    # break the action itself, so they are swallowed.
    def log_admin_action(action, target: nil, details: nil)
      AdminAuditLog.record!(admin_user: current_admin_user, action: action, target: target, details: details)
    rescue StandardError
      nil
    end

    public

    # Override this value to specify the number of elements to display at a time
    # on index pages. Defaults to 20.
    # def records_per_page
    #   params[:per_page] || 20
    # end
  end
end
