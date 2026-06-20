module Admin
  class UsersController < Admin::ApplicationController
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
