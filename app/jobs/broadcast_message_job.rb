class BroadcastMessageJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    payload = MessageSerializer.render_as_hash(message, view: :default)
    ActionCable.server.broadcast("conversation_#{message.conversation_id}", { message: payload })
  end
end
