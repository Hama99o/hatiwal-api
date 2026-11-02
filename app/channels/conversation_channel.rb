class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:conversation_id])

    if conversation && participant?(conversation)
      # SHOP-3: the team of a shop chat gets the members-only stream (the same
      # messages + `sent_by`); everyone else, the buyer included, the plain one.
      team = conversation.shop_face.present? && conversation.seller_side?(current_user)
      stream_from(team ? BroadcastMessageJob.team_stream(conversation.id) : "conversation_#{conversation.id}")
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
