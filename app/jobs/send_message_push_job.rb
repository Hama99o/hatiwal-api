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
    return if recipient.nil?
    if recipient.push_token.blank?
      # Normally silent: plenty of users have no token. But a Support reply is
      # an admin waiting on someone, and returning quietly made "can never be
      # notified" look identical to "notified". Half of the doubled silence in
      # docs/PUSH_NOTIFICATIONS.md; the admin thread page shows it too.
      if sender.support_account?
        Rails.logger.warn("[push] Support reply #{message.id} not pushed: user #{recipient.id} has no push token")
      end
      return
    end
    return if recipient.account_blocked?
    return if recipient.blocked?(sender) || sender.blocked?(recipient)

    result = Notifications::ExpoPushService.deliver(
      token: recipient.push_token,
      title: title_for(sender, recipient),
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
    return message.body.to_s.truncate(BODY_MAX) unless key

    I18n.with_locale(recipient_locale(recipient)) { I18n.t(key) }
  end

  # A person's name is their name in every language. The Support account's
  # stored name is English, though, and a push title is composed HERE and shown
  # by the OS verbatim — a client can't relabel it — so Support's title is
  # localized to the recipient like the body.
  def title_for(sender, recipient)
    return sender.full_name unless sender.support_account?

    I18n.with_locale(recipient_locale(recipient)) { I18n.t("push.support.title") }
  end

  # A language with no locale file is not an available locale, and
  # I18n.with_locale RAISES on it — which is how every non-text push to an Urdu
  # user failed before ur.yml existed. Fall back instead, so the next language
  # added to User::SUPPORTED_LANGUAGES without a locale file degrades to the
  # default rather than silently dropping pushes.
  def recipient_locale(recipient)
    locale = recipient.preferred_language.presence&.to_sym
    locale && I18n.locale_available?(locale) ? locale : I18n.default_locale
  end
end
