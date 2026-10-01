# How much admin email may go out, and to whom — the ONE place to change when
# the sender changes (docs/EMAIL.md). Today the sender is a free Gmail account
# (~500 recipients / rolling 24h); 450 leaves headroom for account mail
# (confirmations, password resets) that is not counted here.
class Admin::MailQuota
  DAILY_LIMIT = 450
  WINDOW = 24.hours

  class DevRecipientNotAllowed < StandardError; end

  def self.sent_in_window(now: Time.current)
    AdminEmail.where(status: :sent, sent_at: (now - WINDOW)..now).count
  end

  def self.remaining(now: Time.current)
    [ DAILY_LIMIT - sent_in_window(now: now), 0 ].max
  end

  # When the oldest send in the window drops out, freeing room.
  def self.room_at(now: Time.current)
    oldest = AdminEmail.where(status: :sent, sent_at: (now - WINDOW)..now).minimum(:sent_at)
    oldest && oldest + WINDOW
  end

  # Development SMTP sends REAL mail (development.rb), and a dev database may
  # hold a copy of production users. So in development, admin email may only
  # go to the mail account itself — and anything else RAISES rather than being
  # skipped, so a mistake is loud. Discipline is not a guard; this is.
  def self.dev_allowlist
    [ Rails.application.config.x.mail_sender ]
  end

  def self.assert_dev_recipient_allowed!(email)
    return unless Rails.env.development?
    return if dev_allowlist.include?(email.to_s.downcase)

    raise DevRecipientNotAllowed,
          "development may only email #{dev_allowlist.join(', ')} (refused #{email}); dev SMTP sends real mail"
  end
end
