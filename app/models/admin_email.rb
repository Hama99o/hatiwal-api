# An email an admin sent to one user, from the Hatiwal mail account
# (docs/EMAIL.md): either one-to-one (Messages) or one recipient of a bulk
# send (admin_bulk_email). Created only after preview + explicit confirm.
class AdminEmail < ApplicationRecord
  belongs_to :admin_user
  belongs_to :user
  belongs_to :admin_bulk_email, optional: true

  # sending: claimed by a worker, SMTP in progress. cancelled: a bulk send was
  # stopped before this one went. Values are append-only.
  enum :status, { queued: 0, sent: 1, failed: 2, sending: 3, cancelled: 4 }

  SUBJECT_MAX = 200
  BODY_MAX = 10_000

  validates :subject, presence: true, length: { maximum: SUBJECT_MAX }
  validates :body, presence: true, length: { maximum: BODY_MAX }
  validate :recipient_can_receive_email, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def deliver_later!
    AdminEmailDeliveryJob.perform_later(id)
  end

  # Claim, then send, then record — the one place "sent" is decided.
  #
  # The claim is a conditional UPDATE (queued → sending): only one worker can
  # win it, so a retried or duplicated job can never mail the same person twice.
  # Email can't be unsent. Returns false if someone else had it (or it was
  # cancelled); never raises — a failure is recorded on the row instead.
  def deliver!
    # updated_at marks WHEN it was claimed: the bulk job treats a row "sending"
    # for too long as interrupted, so the claim must be timestamped.
    claimed = self.class.where(id: id, status: :queued)
                  .update_all(status: self.class.statuses[:sending], updated_at: Time.current)
    return false unless claimed == 1

    Admin::MailQuota.assert_dev_recipient_allowed!(user.email)
    message = admin_bulk_email ? AdminMessageMailer.bulk(self) : AdminMessageMailer.direct(self)
    # development.rb swallows delivery errors; "sent" must mean the server
    # accepted it, in every environment.
    message.raise_delivery_errors = true
    message.deliver_now
    update_columns(status: self.class.statuses[:sent], sent_at: Time.current, error: nil)
    true
  rescue StandardError => e
    update_columns(status: self.class.statuses[:failed], error: "#{e.class}: #{e.message}".truncate(500))
    false
  end

  private

  def recipient_can_receive_email
    errors.add(:user, "can't be emailed (#{user.email_refusal_reason})") if user && !user.emailable?
  end
end
