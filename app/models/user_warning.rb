# A moderation strike issued to a user. Warnings accumulate; once a user has
# User::WARNING_BLOCK_THRESHOLD *active* (non-expired) warnings they are
# auto-suspended (see User#issue_warning!). Each warning is active for
# ACTIVE_PERIOD, then it decays — which is how a user "earns back" warnings over
# time with good behavior.
#
# NOTE: named UserWarning, not Warning — `Warning` is a built-in Ruby module and
# can't be used as an autoloaded model constant.
class UserWarning < ApplicationRecord
  # How long a warning counts toward the block threshold before it decays.
  ACTIVE_PERIOD = 30.days

  belongs_to :user
  belongs_to :admin_user, optional: true

  # A warning issued from a report stores a CODE ("report:fraud"), shown in the
  # reader's language (d0 hunt 2026-10-09: it stored English, "Reported as
  # fraud", which the apps showed verbatim to ps/fa/ur users). Old English rows
  # are recognised too. A reason an admin typed is shown as typed.
  REPORT_REASON = /\Areport:(\w+)\z/
  LEGACY_REPORT_REASON = /\AReported as (.+)\z/

  def self.report_reason(report_reason) = "report:#{report_reason}"

  def display_reason(locale = user&.reader_locale)
    code = reason[REPORT_REASON, 1] || reason[LEGACY_REPORT_REASON, 1]&.tr(" ", "_")
    return reason unless code && Report.reasons.key?(code)

    I18n.t("accounts.report_warning.#{code}", locale: locale || I18n.default_locale)
  end

  enum :category, {
    spam: 0,
    fraud: 1,
    inappropriate: 2,
    prohibited_item: 3,
    harassment: 4,
    other: 5
  }, prefix: :category

  validates :reason, presence: true
  validates :expires_at, presence: true

  before_validation :set_expiry, on: :create

  scope :active,  -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :recent,  -> { order(created_at: :desc) }

  def active?
    expires_at > Time.current
  end

  # Display label for the issuing admin (no AdminUser dashboard to link to).
  def admin_label
    admin_user&.to_s || "—"
  end

  private

  def set_expiry
    self.expires_at ||= Time.current + ACTIVE_PERIOD
  end
end
