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
    include Admin::Filterable

    protect_from_forgery with: :exception

    before_action :authenticate_admin_user!
    helper_method :support_awaiting_reply_count, :waiting_verifications_count


    private

    # NEWEST FIRST, everywhere.
    #
    # Administrate sets no default order, so an index came back in whatever order
    # Postgres felt like returning. For an append-mostly table that is usually
    # insertion order, but it is not guaranteed and it is visibly not what an
    # operator wants on a moderation screen.
    #
    # These two hooks are Administrate 1.0's own seam: `sorting_attribute` falls
    # back to `default_sorting_attribute` ONLY when no sort param is present, so
    # clicking a column header still re-sorts exactly as before.
    #
    # Safe on the base controller because every one of the eight dashboard models
    # has a created_at column — admin_audit_logs, admin_users, blocks, categories,
    # listings, reports, users, user_warnings, all checked against db/schema.rb. A
    # model without one would need its own default rather than inheriting this.
    #
    # Private, as in the gem: a public method on a controller is an action.
    def default_sorting_attribute
      :created_at
    end

    def default_sorting_direction
      :desc
    end

    # Navigation badge: support threads waiting on us, shown on every admin page
    # so a new message gets noticed without anyone opening the inbox.
    def support_awaiting_reply_count
      @support_awaiting_reply_count ||= Conversation.awaiting_support_reply.count
    end

    # Navigation badge: VER-1 verification requests waiting for a decision.
    def waiting_verifications_count
      @waiting_verifications_count ||= VerificationRequest.requested.count
    end

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
