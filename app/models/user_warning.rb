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

  # A warning belongs to EITHER a user (personal strike) OR a shop (the business
  # answers for what it sells, owner 2026-10-16) — exactly one. `posted_by` is the
  # team member who posted a taken-down shop listing; `listing` is what it was about.
  belongs_to :user, optional: true
  belongs_to :shop, optional: true
  belongs_to :posted_by, class_name: User.name, optional: true
  belongs_to :listing, optional: true
  belongs_to :admin_user, optional: true
  # Who cancelled it (owner, 2026-10-19: "Revoke warning" in the admin).
  belongs_to :revoked_by, class_name: AdminUser.name, optional: true

  validate :exactly_one_subject

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

  # A revoked warning never counts again, and the person no longer sees it.
  scope :not_revoked, -> { where(revoked_at: nil) }
  scope :active,  -> { not_revoked.where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current).or(where.not(revoked_at: nil)) }
  scope :recent,  -> { order(created_at: :desc) }

  def active?
    !revoked? && expires_at > Time.current
  end

  def revoked?
    revoked_at.present?
  end

  # Cancel a warning (a mistake, or an appeal the admin accepts). The row stays
  # for the history. A user auto-suspended by strikes is reinstated at once when
  # this brings them under the threshold; a suspended SHOP is not reactivated
  # here, because its suspension may have been a manual one (the admin decides).
  # Returns false when it was already revoked.
  #
  # The check runs under a row lock on a fresh read: two revokes sent at once
  # (two admins, or a double click) would otherwise both pass `revoked?` on
  # their own copy, the second overwriting the reason (QA 2026-10-19).
  def revoke!(admin_user:, reason:)
    revoked_now = with_lock do
      next false if revoked?

      update!(revoked_at: Time.current, revoked_by: admin_user, revoke_reason: reason)
      true
    end
    return false unless revoked_now

    user&.reinstate_if_decayed!
    true
  end

  # Display label for the issuing admin (no AdminUser dashboard to link to).
  def admin_label
    admin_user&.to_s || "—"
  end

  def revoked_by_label
    revoked_by&.to_s
  end

  # Admin field labels (the admin is English-only, so not in config/locales,
  # which must carry every key in all locales). Administrate showed "Revoked by label".
  ADMIN_FIELD_LABELS = { "admin_label" => "Issued by", "revoked_by_label" => "Revoked by" }.freeze

  def self.human_attribute_name(attribute, options = {})
    ADMIN_FIELD_LABELS[attribute.to_s] || super
  end

  private

  # A warning strikes a user OR a shop, never both and never neither.
  def exactly_one_subject
    return if user_id.present? ^ shop_id.present?

    errors.add(:base, "a warning belongs to exactly one of a user or a shop")
  end

  def set_expiry
    self.expires_at ||= Time.current + ACTIVE_PERIOD
  end
end
