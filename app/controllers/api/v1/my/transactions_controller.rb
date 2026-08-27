# The seller/buyer view of the sales ledger.
#
#   GET    /my/transactions      — the caller's own transactions, both roles (TASK-TX01)
#   PATCH  /my/transactions/:id  — correct a recorded sale (SF-B4)
#   DELETE /my/transactions/:id  — void a recorded sale (SF-B4)
#
# PATCH and DELETE are the "Undo" on the mark-sold toast AND the Sales screen's
# editable row — one pair of endpoints, no separate "correction form" concept.
# There is deliberately no server-side undo WINDOW: the only guard that matters
# is that a sale with a review already attached cannot be voided or reassigned
# (Transaction::REVIEWED_SALE_ERROR), not a clock.
class Api::V1::My::TransactionsController < Api::V1::BaseController
  before_action :set_transaction, only: [ :update, :destroy ]

  def index
    # Eager-load everything TransactionSerializer touches so listing thumbnail
    # and buyer/seller avatar lookups don't issue a query per row (N+1) —
    # same includes shape used by every other list endpoint that renders
    # thumbnail_url/avatar_url (see My::SavedListingsController, etc.).
    transactions = policy_scope(
      Transaction.ordered.includes(
        { listing: { images_attachments: { blob: { variant_records: { image_attachment: :blob } } } } },
        { buyer: { avatar_attachment: :blob } },
        { seller: { avatar_attachment: :blob } }
      )
    )
    transactions = transactions.as_buyer(current_user)  if params[:as] == "buyer"
    transactions = transactions.as_seller(current_user) if params[:as] == "seller"
    # SF-B5 — the Sales screen reads one listing's ledger:
    # GET /my/transactions?listing_id=42&as=seller&status=sold
    transactions = transactions.for_listing(params[:listing_id]) if params[:listing_id].present?
    transactions = transactions.where(status: params[:status]) if valid_status?

    paginate_blue(TransactionSerializer, transactions, extra: { current_user: current_user })
  end

  # PATCH /my/transactions/:id — quantity, buyer and/or price.
  #
  # `quantity: 0` (or any non-positive value) is how the client says "this sale
  # did not happen" through the same endpoint; the model treats it as a void.
  def update
    authorize @transaction, :update?

    @transaction.listing.correct_sold_transaction!(
      transaction: @transaction, **correction_params
    )
    render_correction_response(@transaction.destroyed? ? nil : @transaction.reload)
  rescue Listing::CorrectionBlocked => e
    render_reviewed_sale_refusal(e)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  # DELETE /my/transactions/:id — "Undo" / the ledger row's Delete. Restores the
  # units to stock, gives back the trust counters, and re-opens the listing if
  # this sale was what retired it.
  def destroy
    authorize @transaction, :destroy?

    @transaction.listing.correct_sold_transaction!(transaction: @transaction, quantity: 0)
    render_correction_response(nil)
  rescue Listing::CorrectionBlocked => e
    render_reviewed_sale_refusal(e)
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable_entity(e.record)
  end

  private

  def set_transaction
    # policy_scope restricts to rows where the caller is the buyer or the seller;
    # the policy then narrows write access to the seller of a SOLD row.
    @transaction = policy_scope(Transaction).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end

  # Flat params, matching the lifecycle-command convention
  # My::ListingsController#reserve/#sold already established (`buyer_id`,
  # `final_price`, `clear_buyer`, `quantity`) — a correction is a command about a
  # sale, not a REST update of an arbitrary resource, and reusing the same four
  # names means the client sends the same shape it already builds.
  def correction_params
    permitted = params.permit(:quantity, :buyer_id, :final_price, :clear_buyer)
    {
      quantity:    permitted[:quantity],
      buyer_id:    permitted[:buyer_id],
      final_price: permitted[:final_price],
      clear_buyer: ActiveModel::Type::Boolean.new.cast(permitted[:clear_buyer]) || false
    }
  end

  # Always returns the listing, rendered :owner_detailed, so the client can
  # repaint stock, status and the `sale` block from one response instead of
  # refetching. `transaction` is absent when the sale was voided — there is
  # nothing left to render.
  def render_correction_response(txn)
    payload = {
      listing: ListingSerializer.render_as_hash(@transaction.listing.reload, view: :owner_detailed)
    }
    payload[:transaction] = TransactionSerializer.render_as_hash(txn, current_user: current_user) if txn
    render_ok(payload)
  end

  # The one deliberate refusal (Transaction::REVIEWED_SALE_ERROR). Carries a
  # stable `code` so the client renders its own localized copy
  # (`listing.sale.voidBlockedReviewed`) rather than this English sentence.
  def render_reviewed_sale_refusal(error)
    render_unprocessable_entity(error.message, code: Transaction::REVIEWED_SALE_CODE)
  end

  # Only the two real enum values; anything else is ignored rather than 500ing on
  # ArgumentError from the enum.
  def valid_status?
    params[:status].present? && Transaction.statuses.key?(params[:status].to_s)
  end
end
