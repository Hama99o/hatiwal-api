# POST /api/v1/support_conversation — the caller's thread with Hatiwal Support,
# created on first call and returned as-is after that (idempotent).
#
# Once it exists it is an ordinary conversation: messages go through
# MessagesController, and it is listed by ConversationsController#index (pinned
# first). Only the app version with support messaging has a button that calls
# this, which is why a USER-created support thread is always safe to serve —
# see docs/SUPPORT_MESSAGING.md.
#
# Owner, 2026-10-12: Support is per identity. With `shop_id`, the SHOP's thread
# (any member may open it; it is shown only while that shop is selected);
# without, the caller's own (Buyer mode and Seller as Me).
class Api::V1::SupportConversationsController < Api::V1::BaseController
  def create
    authorize Conversation, :start_support?

    conversation = params[:shop_id].present? ? shop_thread : Conversation.support_thread_for!(current_user)
    render_blue(ConversationSerializer, conversation, view: :detailed, options: { current_user: current_user })
  end

  private

  def shop_thread
    shop = Shop.find(params[:shop_id])
    authorize shop, :member?
    Conversation.shop_support_thread_for!(shop)
  end
end
