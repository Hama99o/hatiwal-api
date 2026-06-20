# Immutable record of an admin moderation action (block, warn, take-down, …).
# Accountability: this surface can change anything about anyone, so every action
# is logged with who did it, to whom/what, and why.
class AdminAuditLog < ApplicationRecord
  belongs_to :admin_user, optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # Display label for the admin (there is no AdminUser dashboard to link to).
  def admin_label
    admin_user&.to_s || "—"
  end

  def self.record!(admin_user:, action:, target: nil, details: nil)
    create!(admin_user: admin_user, action: action, target: target, details: details)
  end
end
