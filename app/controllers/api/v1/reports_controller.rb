class Api::V1::ReportsController < Api::V1::BaseController
  def create
    @report = Report.new(report_params.merge(reporter: current_user))
    authorize @report

    if @report.save
      render json: { message: "Report submitted" }, status: :created
    else
      render_unprocessable_entity(@report)
    end
  end

  private

  def report_params
    params.require(:report).permit(
      :reportable_type, :reportable_id, :reason, :description
    )
  end
end
