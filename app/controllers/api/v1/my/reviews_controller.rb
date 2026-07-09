# GET /api/v1/my/reviews/pending — sold transactions where the caller is a
# party but hasn't left a review yet. Drives the "rate your recent deals"
# prompt. Returns TransactionSerializer rows so the app knows the counterparty.
class Api::V1::My::ReviewsController < Api::V1::BaseController
  def pending
    authorize :review, :pending?

    already_reviewed = Review.where(reviewer_id: current_user.id).select(:transaction_id)
    sales = policy_scope(Transaction).sold
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
