# A new account gets one welcome message from Hatiwal Support, in its own
# language, so its first look at Messages is a real conversation it can reply
# to (owner's request, 2026-10-02).
#
# Enqueued by the two doors into account creation, email sign-up
# (Auth::RegistrationsController) and Google (Auth::GoogleAuthController), never
# by a model callback: docs/SUPPORT_MESSAGING.md forbids seeds, migrations and
# backfills from creating support threads, and a callback would.
#
# The thread comes from Conversation.admin_support_thread_for, the gate. With
# SUPPORT_ADMIN_INITIATE off it returns nil and nothing is sent.
class WelcomeSupportMessageJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    thread = Conversation.admin_support_thread_for(user)
    return unless thread
    # Once only: a retried job, or a user who already wrote to Support, gets no
    # second welcome.
    return if thread.messages.exists?

    message = thread.messages.create!(user: thread.seller, kind: :text, body: welcome_text(user))
    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id)
  end

  private

  # Same fallback as SendMessagePushJob#recipient_locale: a blank or unknown
  # language gets the default locale, never a raise.
  def welcome_text(user)
    locale = user.preferred_language.presence&.to_sym
    locale = I18n.default_locale unless locale && I18n.locale_available?(locale)
    I18n.with_locale(locale) { I18n.t("support.welcome") }
  end
end
