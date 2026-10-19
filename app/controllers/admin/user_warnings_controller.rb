module Admin
  # Warnings are issued from the user page (Admin::UsersController#warn) or by a
  # flag take-down, so there are no new/create/edit actions. `revoke` cancels one.
  class UserWarningsController < Admin::ApplicationController
    filter :category, :select, options: -> { UserWarning.categories.keys }
    # UserWarning already models active/expired as scopes; reuse them rather than
    # re-expressing the expiry comparison here.
    filter :state, :scope, options: -> { %w[active expired] }, scope: lambda { |rel, v|
      v == "active" ? rel.active : rel.expired
    }
    filter :created, :date_range, column: :created_at, label: "Issued"

    # Revoke (owner, 2026-10-19): a warning given by mistake, or an appeal the
    # admin accepts. It stops counting at once and the person no longer sees it;
    # the row stays, with who revoked it and why. Audit-logged.
    def revoke
      warning = find_resource(params[:id])
      subject = warning.user || warning.shop
      back = subject ? [ namespace, subject ] : [ namespace, warning ]
      reason = params[:revoke_reason].to_s.strip
      return redirect_to(back, alert: "Write why the warning is revoked.") if reason.blank?
      return redirect_to(back, alert: "This warning was already revoked.") unless warning.revoke!(admin_user: current_admin_user, reason: reason)

      log_admin_action("revoke_warning", target: subject, details: "warning ##{warning.id}: #{reason}")
      redirect_to back, notice: revoke_notice(subject)
    end

    private

    def revoke_notice(subject)
      case subject
      when User
        reinstated = subject.active? ? "" : " Still #{subject.status}: use Unblock if they should be back."
        "Warning revoked — #{subject.full_name} now has #{subject.active_warnings_count}/#{User::WARNING_BLOCK_THRESHOLD}.#{reinstated}"
      when Shop
        still = subject.suspended? ? " The shop is still suspended: use Reactivate if it should be live." : ""
        "Warning revoked — #{subject.name} now has #{subject.active_warnings_count}/#{Shop::SHOP_WARNING_BLOCK_THRESHOLD}.#{still}"
      else
        "Warning revoked."
      end
    end
  end
end
