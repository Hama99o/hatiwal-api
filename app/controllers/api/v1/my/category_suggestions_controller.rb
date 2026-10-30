# Sell with a photo (docs/SELL_WITH_PHOTO.md).
#
# POST /my/listings/category_suggestion         — one photo → a category id, or 204
# POST /my/listings/category_suggestion/outcome — what the seller did with it
#
# Every answer and every outcome is ONE log line ("category_suggestion
# event=…"): ids and numbers only, never the photo or anything the seller wrote.
# Counting them after release gives the real precision, to tune MIN_CONFIDENCE.
class Api::V1::My::CategorySuggestionsController < Api::V1::BaseController
  include LookedAtPhotoParam
  include NumberParam

  UNAVAILABLE = "Category suggestions are not available right now.".freeze
  INVALID_OUTCOME = "Unknown outcome.".freeze

  # One photo embed costs what an image search does (~0.3-0.5 s of CPU).
  throttle to: 30, within: 10.minutes, by: :user, only: :create
  throttle to: 120, within: 10.minutes, by: :ip, only: :create
  throttle to: 60, within: 10.minutes, by: :user, only: :outcome

  def create
    authorize Listing, :category_suggestion?
    return render_unavailable unless CategorySuggestion.enabled?

    bytes, error = read_looked_at_photo
    return render_looked_at_photo_error(error) if error

    result = suggestion_for(bytes)
    return no_suggestion unless result

    log_event("suggested", result.category_id, result.confidence)
    render_ok(result.to_h)
  rescue ImageSearch::Embedder::InvalidImage
    render_looked_at_photo_error(:invalid_image)
  rescue ImageSearch::Embedder::Unavailable
    render_unavailable
  end

  def outcome
    authorize Listing, :category_suggestion?
    category_id = number_param(:category_id, integer: true)
    unless CategorySuggestion::OUTCOMES.include?(params[:outcome]) && category_id
      return render_unprocessable_entity(INVALID_OUTCOME, code: :invalid_outcome)
    end

    confidence = number_param(:confidence)
    log_event(params[:outcome], category_id, confidence&.to_f&.round(3))
    head :no_content
  end

  private

  # A blank photo (a covered lens) has nothing to suggest: no error.
  def suggestion_for(bytes)
    CategorySuggestion.call(ImageSearch::Embedder.embed(bytes))
  rescue ImageSearch::Embedder::PlainImage
    nil
  end

  def no_suggestion
    log_event("none")
    head :no_content
  end

  def log_event(event, category_id = nil, confidence = nil)
    line = "category_suggestion event=#{event}"
    line += " category_id=#{category_id}" if category_id
    line += " confidence=#{confidence}" if confidence
    Rails.logger.info(line)
  end

  def render_unavailable
    render_coded_error(UNAVAILABLE, code: :category_suggestion_unavailable, status: :service_unavailable)
  end
end
