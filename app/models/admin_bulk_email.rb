# One bulk email: the segment it went to, its per-language content, and the
# state of the run. Recipients are the admin_emails rows snapshot at confirm.
class AdminBulkEmail < ApplicationRecord
  belongs_to :admin_user
  has_many :admin_emails, dependent: :restrict_with_exception

  # sending → finished, or paused at the daily cap (resumable), or stopped.
  enum :status, { sending: 0, paused_daily_limit: 1, stopped: 2, finished: 3 }

  LOCALES = User::SUPPORTED_LANGUAGES
  LANGUAGE_NAMES = { "en" => "English", "ps" => "Pashto", "fa" => "Dari", "ur" => "Urdu" }.freeze

  validates :fallback_locale, inclusion: { in: LOCALES }
  validate :fallback_has_content

  scope :recent, -> { order(created_at: :desc) }

  # { "en" => { "subject" => "...", "body" => "..." }, ... } with only filled
  # languages kept: a language counts only when BOTH subject and body exist.
  def self.normalize_content(raw)
    LOCALES.each_with_object({}) do |loc, acc|
      entry = (raw || {})[loc] || {}
      subject = entry["subject"].to_s.strip
      body = entry["body"].to_s.strip
      acc[loc] = { "subject" => subject, "body" => body } if subject.present? && body.present?
    end
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
