# Sends a push notification to the recipient of a newly-created message, so they
# see it even when the app is closed. Enqueued from MessagesController#create
# alongside BroadcastMessageJob (which only reaches an OPEN app via ActionCable).
#
# Silently no-ops (never raises) when there is nothing/no-one to notify.
class SendMessagePushJob < ApplicationJob
  queue_as :default

  # Non-text messages have no readable body — show a localized label instead.
  PREVIEW_KEYS = {
    "offer" => "push.message.offer",
    "meetup_proposal" => "push.message.meetup",
    "image_message" => "push.message.image",
    "document" => "push.message.document"
  }.freeze

  BODY_MAX = 120

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    conversation = message.conversation
    sender = message.user

    # Only real participant-authored messages notify. Server :system messages
    # (authored by a system user) are skipped.
    return unless sender && [ conversation.buyer_id, conversation.seller_id ].include?(sender.id)

    recipient = conversation.other_participant(sender)
    return if recipient.nil? || recipient.push_token.blank?
    return if recipient.account_blocked?
    return if recipient.blocked?(sender) || sender.blocked?(recipient)

    result = Notifications::ExpoPushService.deliver(
      token: recipient.push_token,
      title: sender.full_name,
      body: preview_for(message, recipient),
      data: { type: "message", conversationId: conversation.id, messageId: message.id }
    )

    # Expo reports the device is gone — drop the stale token so we stop retrying.
    recipient.update_column(:push_token, nil) if result.error.to_s == "DeviceNotRegistered"
  end

  private

  # Localized to the RECIPIENT's language since the device renders this text
  # verbatim. Text messages show their actual content (already in the sender's
  # language); only the non-text labels are translated.
  def preview_for(message, recipient)
    key = PREVIEW_KEYS[message.kind]
    locale = recipient.preferred_language.presence || I18n.default_locale
    return message.body.to_s.truncate(BODY_MAX) unless key

    I18n.with_locale(locale) { I18n.t(key) }
  end
end
