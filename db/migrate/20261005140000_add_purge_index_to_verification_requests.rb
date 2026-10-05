# VER-1, scale: PurgeVerificationFilesJob scans for decided requests whose files
# are still there (VerificationRequest.purgeable). Partial, so the index only
# holds rows that still have files to delete and stays small at any size.
class AddPurgeIndexToVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    add_index :verification_requests, :decided_at,
              where: "files_purged_at IS NULL AND decided_at IS NOT NULL",
              name: "index_verification_requests_purgeable"
  end
end
