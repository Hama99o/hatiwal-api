# GET /my/transactions — the caller's own completed/in-progress transactions,
# both as buyer and as seller. Optional `?as=buyer` / `?as=seller` narrows to
# one role. TASK-TX01.
class Api::V1::My::TransactionsController < Api::V1::BaseController
  def index
    # Eager-load everything TransactionSerializer touches so listing thumbnail
    # and buyer/seller avatar lookups don't issue a query per row (N+1) —
    # same includes shape used by every other list endpoint that renders
    # thumbnail_url/avatar_url (see My::SavedListingsController, etc.).
    transactions = policy_scope(
      Transaction.ordered.includes(
        { listing: { images_attachments: :blob } },
        { buyer: { avatar_attachment: :blob } },
        { seller: { avatar_attachment: :blob } }
      )
    )
    transactions = transactions.as_buyer(current_user)  if params[:as] == "buyer"
    transactions = transactions.as_seller(current_user) if params[:as] == "seller"

    paginate_blue(TransactionSerializer, transactions, extra: { current_user: current_user })
  end
end
