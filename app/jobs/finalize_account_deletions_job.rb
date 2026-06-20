# Daily sweep that permanently anonymizes accounts whose 30-day deletion grace
# period (User::DELETION_GRACE_PERIOD) has elapsed and which were not restored.
# Already-finalized accounts (deleted_at present) are skipped.
class FinalizeAccountDeletionsJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = User::DELETION_GRACE_PERIOD.ago
    User.where(deleted_at: nil)
        .where.not(deletion_scheduled_at: nil)
        .where(deletion_scheduled_at: ..cutoff)
        .find_each(&:anonymize_account!)
  end
end
