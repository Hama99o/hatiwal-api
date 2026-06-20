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
