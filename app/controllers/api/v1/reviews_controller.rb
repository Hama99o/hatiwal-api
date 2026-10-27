# Reviews on a sold Transaction. Double-blind — see Review for the reveal rules.
#   GET   /api/v1/users/:user_id/reviews   — a user's visible reviews (public)
#   POST  /api/v1/transactions/:transaction_id/reviews — leave a review
#   PATCH /api/v1/reviews/:id              — edit your own review while hidden
class Api::V1::ReviewsController < Api::V1::BaseController
  # OFFLINE §10.1: a retried write with the same Idempotency-Key runs once.
  idempotent :create, :update

  # Hunt-2 (1.1.7).
  throttle to: 60, within: 1.day, by: :user, only: %i[create update]

  # A seller's rating is a public trust signal — guests browsing a shared
  # profile must see it without logging in. Only :index is opened up; leaving
  # a review (create) / editing one (update) still require authentication.
  skip_before_action :authenticate_user!, only: :index
  skip_before_action :reject_blocked_user!, only: :index
  before_action :authenticate_optional!, only: :index

  def index
    user = User.find(params[:user_id])
    reviews = policy_scope(Review).visible.for_reviewee(user).about_person.ordered
    reviews = reviews.where(role: params[:role]) if Review.roles.key?(params[:role])

    paginate_blue(ReviewSerializer, reviews.includes(reviewer: { avatar_attachment: :blob }))
  end

  def create
    sale = Transaction.find(params[:transaction_id])
    review = build_review(sale)
    authorize review

    review.submit!
    render_blue(ReviewSerializer, review, status: :created)
  rescue ActiveRecord::RecordInvalid => e
    # OFFLINE §5 row 23: a stable code, so a review queued offline that another
    # device already left is DONE for the app, not a refusal.
    code = e.record.errors.of_kind?(:reviewer_id, :taken) ? :already_reviewed : nil
    render_unprocessable_entity(e.record, code: code)
  rescue ActiveRecord::RecordNotUnique
    render_unprocessable_entity("You have already reviewed this sale", code: :already_reviewed)
  end

  def update
    review = Review.find(params[:id])
    authorize review

    # OFFLINE §10.2: with `base` (what the phone saw), a field changed on the
    # author's other device meanwhile is not overwritten; the rest applies; 409.
    edit = Edits::WithBase.split(review, review_params, review_base)
    if review.update(edit.attrs)
      return render_review_conflict(review, edit.conflicts) if edit.conflicts.any?

      render_blue(ReviewSerializer, review)
    else
      render_unprocessable_entity(review)
    end
  end

  private

  # The reviewer is whichever party the caller is; the reviewee + role are the
  # opposite side. Validations reject the call if the caller is neither party.
  def build_review(sale)
    caller_is_buyer = sale.present? && current_user.id == sale.buyer_id
    Review.new(
      sale: sale,
      reviewer: current_user,
      reviewee: caller_is_buyer ? sale&.seller : sale&.buyer,
      role: caller_is_buyer ? :of_seller : :of_buyer,
      rating: review_params[:rating],
      comment: review_params[:comment]
    )
  end

  def review_params
    params.require(:review).permit(:rating, :comment)
  end

  def review_base
    base = params.dig(:review, :base)
    base.respond_to?(:permit) ? base.permit(:rating, :comment).to_h : {}
  end

  def render_review_conflict(review, conflicts)
    render_ok({ review: ReviewSerializer.render_as_hash(review), code: "edit_conflict", fields: conflicts }, status: :conflict)
  end
end
