class Api::V1::ReportsController < Api::V1::BaseController
  def index
    reports = policy_scope(Report).where(reporter: current_user)
                                  .includes(:reportable)
                                  .order(created_at: :desc)
    paginate_blue(ReportSerializer, reports, extra: { view: :list })
  end

  def create
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
