# VER-1: apply for the Verified badge, read the status card, cancel while it is
# waiting. Spec: hatiwal-mobile/docs/VERIFICATION.md.
#
# Every response is the status card (VerificationStatusSerializer) — never a
# document. `subject=me` (default) or, SHOP-1, `subject=shop:<id>` for a shop the
# caller manages.
class Api::V1::VerificationRequestsController < Api::V1::BaseController
  # Owner rule (1.1.6): a confirmed email before applying, for a person or a shop.
  before_action :require_confirmed_email!, only: :create
  # Spec: 3 requests per day per user. Counted on requests actually SENT
  # (VerificationRequest::DAILY_LIMIT), so blurry uploads that fail validation
  # don't lock anyone out. This throttle is only the anti-script backstop.
  throttle to: 30, within: 1.day, by: :user, only: :create

  before_action :resolve_subject

  # GET /api/v1/verification_requests/current?subject=me|shop:<id>
  def current
    authorize VerificationRequest.new(subject: @subject, requested_by: current_user), :show?
    render_status
  end

  # POST /api/v1/verification_requests (multipart)
  def create
    return render_daily_limit_reached if VerificationRequest.daily_limit_reached?(current_user)

    request = VerificationRequest.new(request_params.merge(subject: @subject, requested_by: current_user))
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
    @subject = request.subject
    render_status
  end

  private

  def render_status(status: :ok)
    render_blue(VerificationStatusSerializer, VerificationStatus.new(@subject.reload), status: status)
  end

  # "me" → the caller. SHOP-1: "shop:<id>" → that shop; whether the caller may
  # apply for it is the policy's call (owner or manager). Anything else → 422.
  def resolve_subject
    raw = params[:subject].presence || "me"
    @subject = if raw == "me"
                 current_user
    elsif (id = raw[/\Ashop:(\d+)\z/, 1])
                 Shop.find_by(id: id)
    end
    render_unprocessable_entity(error_text(:unknown_subject), code: "verification_unknown_subject") if @subject.nil?
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
    params.require(:verification_request).permit(:document_type, :name_on_document, :document_number, :front, :back, :selfie, :proof)
  end
end
