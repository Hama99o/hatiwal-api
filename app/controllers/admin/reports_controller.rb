module Admin
  class ReportsController < Admin::ApplicationController
    # One-click moderation from a report: act on the reported thing AND resolve
    # the report in a single step, so triage is fast.

    def resolve
      report = find_resource(params[:id])
      report.update!(status: :resolved)
      log_admin_action("resolve_report", target: report)
      redirect_to [ namespace, report ], notice: "Report marked resolved."
    end

    def dismiss
      report = find_resource(params[:id])
      report.update!(status: :dismissed)
      log_admin_action("dismiss_report", target: report)
      redirect_to [ namespace, report ], notice: "Report dismissed."
    end

    # Take down the reported listing + resolve.
    def take_down_target
      report = find_resource(params[:id])
      listing = report.reportable
      unless listing.is_a?(Listing)
        return redirect_to([ namespace, report ], alert: "This report is not about a listing.")
      end

      listing.take_down!(reason: "Reported as #{report.reason.humanize.downcase}")
      report.update!(status: :resolved)
      log_admin_action("take_down_listing", target: listing, details: "via report ##{report.id}")
      redirect_to [ namespace, report ], notice: "Listing taken down and report resolved."
    end

    # Warn the reported user (or the seller of the reported listing) + resolve.
    def warn_target
      report = find_resource(params[:id])
      target = user_to_warn(report)
      unless target
        return redirect_to([ namespace, report ], alert: "Could not determine a user to warn.")
      end

      target.issue_warning!(
        admin_user: current_admin_user,
        reason: "Reported as #{report.reason.humanize.downcase}",
        category: warning_category_for(report.reason)
      )
      report.update!(status: :resolved)
      log_admin_action("warn_user", target: target, details: "via report ##{report.id}")
      redirect_to [ namespace, report ], notice: "Warning issued to #{target.full_name} and report resolved."
    end

    private

    # The user a report points at: the reported user, or the listing's seller.
    def user_to_warn(report)
      case report.reportable
      when User then report.reportable
      when Listing then report.reportable.user
      end
    end

    def warning_category_for(reason)
      UserWarning.categories.key?(reason) ? reason : "other"
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
