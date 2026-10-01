# POST /api/v1/support_conversation — the caller's thread with Hatiwal Support,
# created on first call and returned as-is after that (idempotent).
#
# Once it exists it is an ordinary conversation: messages go through
# MessagesController, and it is listed by ConversationsController#index (pinned
# first). Only the app version with support messaging has a button that calls
# this, which is why a USER-created support thread is always safe to serve —
# see docs/SUPPORT_MESSAGING.md.
class Api::V1::SupportConversationsController < Api::V1::BaseController
  def create
    authorize Conversation, :start_support?

    conversation = Conversation.support_thread_for!(current_user)
    render_blue(ConversationSerializer, conversation, view: :detailed, options: { current_user: current_user })
  end
end
