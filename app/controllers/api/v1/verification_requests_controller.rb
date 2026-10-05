# VER-1: apply for the Verified badge, read the status card, cancel while it is
# waiting. Spec: hatiwal-mobile/docs/VERIFICATION.md.
#
# Every response is the status card (VerificationStatusSerializer) — never a
# document. Only `subject=me` exists today; `shop:<id>` arrives with SHOP-1.
class Api::V1::VerificationRequestsController < Api::V1::BaseController
  # Spec: 3 requests per day per user. Counted on requests actually SENT
  # (VerificationRequest::DAILY_LIMIT), so blurry uploads that fail validation
  # don't lock anyone out. This throttle is only the anti-script backstop.
  throttle to: 30, within: 1.day, by: :user, only: :create

  before_action :require_subject_me

  # GET /api/v1/verification_requests/current?subject=me
  def current
    authorize VerificationRequest.new(subject: current_user, requested_by: current_user), :show?
    render_status
  end

  # POST /api/v1/verification_requests (multipart)
  def create
    return render_daily_limit_reached if VerificationRequest.daily_limit_reached?(current_user)

    request = VerificationRequest.new(request_params.merge(subject: current_user, requested_by: current_user))
    authorize request

    if request.save
      render_status(status: :created)
    else
      render_unprocessable_entity(request)
    end
  rescue ActiveRecord::RecordNotUnique
    render_unprocessable_entity(error_text(:already_requested), code: "verification_already_requested")
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
    render_unprocessable_entity(error_text(:unknown_subject), code: "verification_unknown_subject") unless subject == "me"
  end

  def render_daily_limit_reached
    render_ok({ error: "rate_limited", code: "verification_daily_limit", message: error_text(:daily_limit) },
              status: :too_many_requests)
  end

  # In the caller's own language (the API does not switch locale per request).
  def error_text(key)
    locale = current_user&.preferred_language.presence
    locale = I18n.default_locale unless locale && I18n.locale_available?(locale)
    I18n.t("verification.errors.#{key}", locale: locale)
  end

  def request_params
    params.require(:verification_request).permit(:document_type, :name_on_document, :document_last4, :front, :back, :selfie)
  end
end
