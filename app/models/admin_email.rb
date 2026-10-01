# An email an admin wrote to one user, sent from the Hatiwal mail account
# (docs/EMAIL.md). Created only after preview + explicit confirm; delivered by
# AdminEmailDeliveryJob, which moves it to sent or failed.
class AdminEmail < ApplicationRecord
  belongs_to :admin_user
  belongs_to :user

  enum :status, { queued: 0, sent: 1, failed: 2 }

  SUBJECT_MAX = 200
  BODY_MAX = 10_000

  validates :subject, presence: true, length: { maximum: SUBJECT_MAX }
  validates :body, presence: true, length: { maximum: BODY_MAX }
  validate :recipient_can_receive_email, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def deliver_later!
    AdminEmailDeliveryJob.perform_later(id)
  end

  private

  def recipient_can_receive_email
    errors.add(:user, "can't be emailed (#{user.email_refusal_reason})") if user && !user.emailable?
  end
end
