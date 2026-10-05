# VER-1: apply for the Verified badge, read the status card, cancel while it is
# waiting. Spec: hatiwal-mobile/docs/VERIFICATION.md.
#
# Every response is the status card (VerificationStatusSerializer) — never a
# document. Only `subject=me` exists today; `shop:<id>` arrives with SHOP-1.
class Api::V1::VerificationRequestsController < Api::V1::BaseController
  # Spec: 3 requests per day per user.
  throttle to: 3, within: 1.day, by: :user, only: :create

  before_action :require_subject_me

  # GET /api/v1/verification_requests/current?subject=me
  def current
    authorize VerificationRequest.new(subject: current_user, requested_by: current_user), :show?
    render_status
  end

  # POST /api/v1/verification_requests (multipart)
  def create
    request = VerificationRequest.new(request_params.merge(subject: current_user, requested_by: current_user))
    authorize request

    if request.save
      render_status(status: :created)
    else
      render_unprocessable_entity(request)
    end
  rescue ActiveRecord::RecordNotUnique
    render_unprocessable_entity("A request is already waiting", code: "verification_already_requested")
  end

  # DELETE /api/v1/verification_requests/:id
  def destroy
    request = policy_scope(VerificationRequest).find(params[:id])
    authorize request
    request.cancel!
    render_status
  end

  private

  def render_status(status: :ok)
    render_blue(VerificationStatusSerializer, VerificationStatus.new(current_user.reload), status: status)
  end

  def require_subject_me
    subject = params[:subject].presence || "me"
    render_unprocessable_entity("Unknown subject", code: "verification_unknown_subject") unless subject == "me"
  end

  def request_params
    params.require(:verification_request).permit(:document_type, :name_on_document, :document_last4, :front, :back, :selfie)
  end
end
