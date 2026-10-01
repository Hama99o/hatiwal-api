# One recipient of an IN-APP bulk message: a Message from Hatiwal Support in
# the user's support thread (docs/EMAIL.md, "Bulk message"). Snapshot at
# confirm, delivered by AdminBulkEmailJob.
class AdminBulkInAppDelivery < ApplicationRecord
  belongs_to :admin_bulk_email
  belongs_to :user
  belongs_to :message, optional: true

  # skipped: the gate refused at SEND time (e.g. the flag was turned off while
  # the run was queued). Values are append-only.
  enum :status, { queued: 0, sent: 1, failed: 2, sending: 3, cancelled: 4, skipped: 5 }

  scope :recent_sent, ->(since) { where(status: :sent, sent_at: since..) }

  # Claim, re-check the gate, post, record — never raises; never posts twice
  # (the claim is a conditional UPDATE only one worker can win).
  def deliver!
    claimed = self.class.where(id: id, status: :queued)
                  .update_all(status: self.class.statuses[:sending], updated_at: Time.current)
    return false unless claimed == 1

    # The gate, AGAIN, per recipient at send time — a count at compose is not
    # a guarantee (the flag can flip, a run can wait in the queue). Never the
    # ungated user-side creator (spec/models/support_gate_spec.rb).
    thread = Conversation.admin_support_thread_for(user)
    unless thread
      return finish(:skipped, error: "in-app not allowed at send time: #{Conversation.admin_message_refusal(user)}")
    end

    muted = thread.muted_by_buyer?
    message = thread.messages.build(user: thread.seller, admin_user: admin_bulk_email.admin_user, kind: :text, body: body)
    message.broadcast = true # don't resurface an archived thread (see Message)
    message.save!
    BroadcastMessageJob.perform_later(message.id)
    note = push_decision(muted)
    SendMessagePushJob.perform_later(message.id) if note == "push sent"
    finish(:sent, message: message, push_note: note)
  rescue StandardError => e
    finish(:failed, error: "#{e.class}: #{e.message}".truncate(500))
  end

  private

  # A broadcast push lights up every phone at once: only when chosen, never
  # to someone who archived Support, and honestly reported when impossible.
  def push_decision(muted)
    return "no push (not chosen)" unless admin_bulk_email.push?
    return "no push: archived Support" if muted
    return "push sent" if user.push_token.present?

    "no push token#{": #{user.push_registration_error}" if user.push_registration_error.present?}"
  end

  def finish(status, message: nil, push_note: nil, error: nil)
    update_columns(status: self.class.statuses[status], message_id: message&.id, push_note: push_note,
                   error: error, sent_at: (Time.current if status == :sent))
    status == :sent
  end
end
