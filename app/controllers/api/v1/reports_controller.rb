class Api::V1::ReportsController < Api::V1::BaseController
  # Reporting is a trust tool, so it is also a harassment tool: unbounded, one
  # account can bury a rival seller under reports, or bury the admin queue.
  # Duplicate reports are already rejected by Report's uniqueness rule, so this
  # bounds reports across DIFFERENT targets.
  throttle to: 20, within: 1.day, by: :user, only: :create

  def index
    reports = policy_scope(Report).where(reporter: current_user)
                                  .includes(:reportable)
                                  .order(created_at: :desc)
    paginate_blue(ReportSerializer, reports, extra: { view: :list })
  end

  def create
    # Security (2026-10-08): the client names the type; refuse anything outside
    # Report::REPORTABLE_TYPES before `reportable` constantizes it (it reached
    # any class — Kernel, AdminUser — and an unknown name was a 500).
    unless Report::REPORTABLE_TYPES.include?(report_params[:reportable_type].to_s)
      return render_unprocessable_entity("This cannot be reported", code: :unknown_reportable_type)
    end

    @report = Report.new(report_params.merge(reporter: current_user))
    authorize @report

    if @report.save
      render_ok({ message: "Report submitted" }, status: :created)
    else
      render_unprocessable_entity(@report)
    end
  rescue ActiveRecord::RecordNotUnique
    @report.errors.add(:reportable_id, :already_reported)
    render_unprocessable_entity(@report)
  end

  private

  def report_params
    params.require(:report).permit(
      :reportable_type, :reportable_id, :reason, :description
    )
  end
end
