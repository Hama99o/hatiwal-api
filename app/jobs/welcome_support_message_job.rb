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
#
# It was OFF until mobile 1.1.4 was live on iOS AND Android (owner, 2026-10-02):
# older apps draw the Support thread poorly. Switch: WELCOME_SUPPORT_MESSAGE=true,
# passed to production through config/deploy.yml's secret env since 516c1ec
# (2026-10-03, "welcome message ON in production — mobile 1.1.4 is live on both
# stores"); its value lives in the deploy secrets, never in the repo.
class WelcomeSupportMessageJob < ApplicationJob
  queue_as :default

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("WELCOME_SUPPORT_MESSAGE", "false"))
  end

  # The sign-up doors call this, so nothing is even queued while it is off.
  def self.enqueue_for(user)
    perform_later(user.id) if enabled? && user&.persisted?
  end

  def perform(user_id)
    return unless self.class.enabled?

    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    thread = Conversation.admin_support_thread_for(user)
    return unless thread
    # Once only: a retried job, or a user who already wrote to Support, gets no
    # second welcome.
    return if thread.messages.exists?

    message = thread.messages.create!(user: thread.support_user, kind: :text, body: welcome_text(user))
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
