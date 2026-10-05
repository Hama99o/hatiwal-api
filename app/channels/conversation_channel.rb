class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:conversation_id])

    if conversation && participant?(conversation)
      stream_from "conversation_#{conversation.id}"
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end

  private

  # The buyer, the seller, or (SHOP-3) a member of the chat's shop.
  def participant?(conversation)
    conversation.participant?(current_user)
  end
end
