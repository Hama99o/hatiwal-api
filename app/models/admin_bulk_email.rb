# One bulk email: the segment it went to, its per-language content, and the
# state of the run. Recipients are the admin_emails rows snapshot at confirm.
class AdminBulkEmail < ApplicationRecord
  belongs_to :admin_user
  has_many :admin_emails, dependent: :restrict_with_exception

  # sending → finished, or paused at the daily cap (resumable), or stopped.
  enum :status, { sending: 0, paused_daily_limit: 1, stopped: 2, finished: 3 }

  LOCALES = Admin::LanguageVersions::LOCALES
  LANGUAGE_NAMES = Admin::LanguageVersions::NAMES

  validates :fallback_locale, inclusion: { in: LOCALES }
  validate :fallback_has_content

  scope :recent, -> { order(created_at: :desc) }

  # Only languages with BOTH subject and body (email needs a subject).
  def self.normalize_content(raw)
    Admin::LanguageVersions.new(raw, fallback: "en", subject: true).versions
  end

  def filled_locales = content.keys

  # The version a user with this preferred_language receives.
  def locale_for(preferred)
    content.key?(preferred.to_s) ? preferred.to_s : fallback_locale
  end

  def counts = admin_emails.group(:status).count

  def remaining? = admin_emails.queued.exists?

  private

  def fallback_has_content
    return if content.key?(fallback_locale)

    errors.add(:base, "Write the #{LANGUAGE_NAMES[fallback_locale]} version: it is the fallback for everyone without their own.")
  end
end
