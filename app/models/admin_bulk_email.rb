# One bulk MESSAGE (the table predates in-app, hence the name): the segment,
# its per-language content, the channels (email and/or in-app), and the state
# of the run. Recipients are snapshot at confirm: admin_emails rows for email,
# admin_bulk_in_app_deliveries rows for in-app.
class AdminBulkEmail < ApplicationRecord
  belongs_to :admin_user
  has_many :admin_emails, dependent: :restrict_with_exception
  has_many :in_app_deliveries, class_name: AdminBulkInAppDelivery.name, dependent: :restrict_with_exception

  # sending → finished, or paused at the daily email cap (resumable), or stopped.
  enum :status, { sending: 0, paused_daily_limit: 1, stopped: 2, finished: 3 }

  LOCALES = Admin::LanguageVersions::LOCALES
  LANGUAGE_NAMES = Admin::LanguageVersions::NAMES
  # One in-app broadcast per person per this long — there is no unsubscribe
  # for a Support thread, so frequency is the restraint (docs/EMAIL.md).
  IN_APP_COOLDOWN = 7.days

  validates :fallback_locale, inclusion: { in: LOCALES }
  validate :a_channel_chosen
  validate :fallback_has_content
  validate :in_app_fits_a_chat_message, if: :via_in_app?

  scope :recent, -> { order(created_at: :desc) }

  # A language counts as written with its body — plus a subject only when
  # emailing (in-app messages have no subject).
  def self.normalize_content(raw, subject: true)
    Admin::LanguageVersions.new(raw, fallback: "en", subject: subject).versions
  end

  def filled_locales = content.keys

  def channels = [ ("Email" if via_email?), ("In-app" if via_in_app?) ].compact

  # The version a user with this preferred_language receives.
  def locale_for(preferred)
    content.key?(preferred.to_s) ? preferred.to_s : fallback_locale
  end

  def counts = admin_emails.group(:status).count
  def in_app_counts = in_app_deliveries.group(:status).count

  def remaining? = admin_emails.queued.exists? || in_app_deliveries.queued.exists?

  private

  def a_channel_chosen
    errors.add(:base, "Choose Email, In-app, or both.") unless via_email? || via_in_app?
  end

  def fallback_has_content
    return if content.key?(fallback_locale)

    errors.add(:base, "Write the #{LANGUAGE_NAMES[fallback_locale]} version: it is the fallback for everyone without their own.")
  end

  def in_app_fits_a_chat_message
    too_long = content.select { |_, v| v["body"].to_s.length > Message::BODY_MAX }.keys
    return if too_long.empty?

    errors.add(:base, "In-app messages are at most #{Message::BODY_MAX} characters " \
                      "(#{too_long.map { |l| LANGUAGE_NAMES[l] }.join(', ')} is longer).")
  end
end
