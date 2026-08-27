# GET /api/v1/my/reviews/pending — sold transactions where the caller is a
# party but hasn't left a review yet. Drives the "rate your recent deals"
# prompt. Returns TransactionSerializer rows so the app knows the counterparty.
#
# SF-B3 — `with_counterparty` excludes outside-buyer sales (`buyer_id: nil`).
# Those are real sales but there is nobody to rate: without the filter the seller
# would be prompted to review a buyer who has no account, and the submit would
# 422 on Review's own `belongs_to :reviewee`. A prompt you cannot satisfy is
# worse than no prompt.
class Api::V1::My::ReviewsController < Api::V1::BaseController
  def pending
    authorize :review, :pending?

    already_reviewed = Review.where(reviewer_id: current_user.id).select(:transaction_id)
    sales = policy_scope(Transaction).sold
                                     .with_counterparty
                                     .where.not(id: already_reviewed)
                                     .ordered
                                     .includes(
                                       { listing: { images_attachments: { blob: { variant_records: { image_attachment: :blob } } } } },
                                       { buyer: { avatar_attachment: :blob } },
                                       { seller: { avatar_attachment: :blob } }
                                     )

    paginate_blue(TransactionSerializer, sales, extra: { current_user: current_user })
  end
end
