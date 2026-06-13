class BroadcastMessageJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    # Jobs have no request context — ActiveStorage needs explicit url_options to
    # generate disk-service URLs for attachments (avatars, message files).
    ActiveStorage::Current.url_options = active_storage_url_options

    payload = MessageSerializer.render_as_hash(message, view: :default)
    ActionCable.server.broadcast("conversation_#{message.conversation_id}", { message: payload })
  end

  private

  def active_storage_url_options
    mailer_opts = Rails.application.config.action_mailer.default_url_options || {}
    host = ENV.fetch("APP_HOST", mailer_opts[:host] || "localhost")
    port = ENV.fetch("APP_PORT", mailer_opts[:port] || 3007)
    { host: host, port: port.to_i, protocol: "http" }
  end
end
