module Admin
  class UsersController < Admin::ApplicationController
    # Declared once in Admin::UserFilterSet, because bulk email reuses them: the
    # segment listed here must be exactly the segment that receives a send.
    include Admin::UserFilterSet

    # Block: a manual ban (severe case, bypasses warnings). auto_blocked: false
    # so the decay job never auto-lifts it — only an admin can.
    def block
      user = find_resource(params[:id])
      user.update!(status: :banned, auto_blocked: false, block_reason: params[:block_reason].presence)
      log_admin_action("block_user", target: user, details: user.block_reason)
      redirect_to [ namespace, user ], notice: "#{user.full_name} has been blocked."
    end

    # Unblock: restore to active AND clear active warnings (clean slate), so a
    # decayed/forgiven user isn't immediately re-suspended by leftover strikes.
    def unblock
      user = find_resource(params[:id])
      user.clear_active_warnings!
      user.update!(status: :active, auto_blocked: false, block_reason: nil)
      log_admin_action("unblock_user", target: user)
      redirect_to [ namespace, user ], notice: "#{user.full_name} has been unblocked."
    end

    # Issue a warning (strike). Auto-suspends the user if it reaches the threshold.
    def warn
      user = find_resource(params[:id])
      reason = params[:reason].presence || "Policy violation"
      user.issue_warning!(
        admin_user: current_admin_user,
        reason: reason,
        category: params[:category].presence || :other
      )
      log_admin_action("warn_user", target: user, details: reason)
      notice = if user.suspended? && user.auto_blocked?
        "Warning issued — #{user.full_name} reached #{User::WARNING_BLOCK_THRESHOLD} warnings and was auto-suspended."
      else
        "Warning issued to #{user.full_name} (#{user.active_warnings_count}/#{User::WARNING_BLOCK_THRESHOLD})."
      end
      redirect_to [ namespace, user ], notice: notice
    end

    # "Confirm email now" (owner, 2026-10-08): confirm a user by hand, e.g. one
    # whose confirmation mail never arrived. See User#admin_confirm_email!.
    def confirm_email
      user = find_resource(params[:id])
      dropped = user.unconfirmed_email
      user.admin_confirm_email!
      log_admin_action("confirm_email", target: user,
                                        details: [ user.email, ("dropped pending change to #{dropped}" if dropped) ].compact.join(" · "))
      redirect_to [ namespace, user ], notice: "#{user.email} is confirmed."
    end

    # Administrate's update, plus the "you are verified" Support message when an
    # admin switches the badge ON (off → on only; SupportNoticeJob re-checks it),
    # and an audit line when the admin edits the email "Confirmed at" date.
    def update
      user = requested_resource
      was_verified = user.verified?
      was_confirmed_at = user.confirmed_at
      super
      user.reload
      SupportNoticeJob.enqueue(user, :user_verified) if !was_verified && user.verified?
      return if user.confirmed_at == was_confirmed_at

      log_admin_action("edit_email_confirmed_at", target: user,
                                                  details: "#{was_confirmed_at&.iso8601 || 'not confirmed'} → #{user.confirmed_at&.iso8601 || 'not confirmed'}")
    end

    # Override this method to specify custom lookup behavior.
    # This will be used to set the resource for the `show`, `edit`, and `update`
    # actions.
    #
    # def find_resource(param)
    #   Foo.find_by!(slug: param)
    # end

    # The result of this lookup will be available as `requested_resource`

    # Override this if you have certain roles that require a subset
    # this will be used to set the records shown on the `index` action.
    #
    # def scoped_resource
    #   if current_user.super_admin?
    #     resource_class
    #   else
    #     resource_class.with_less_stuff
    #   end
    # end

    # Override `resource_params` if you want to transform the submitted
    # data before it's persisted. For example, the following would turn all
    # empty values into nil values. It uses other APIs such as `resource_class`
    # and `dashboard`:
    #
    # def resource_params
    #   params.require(resource_class.model_name.param_key).
    #     permit(dashboard.permitted_attributes(action_name)).
    #     transform_values { |value| value == "" ? nil : value }
    # end

    # See https://administrate-demo.herokuapp.com/customizing_controller_actions
    # for more information
  end
end
