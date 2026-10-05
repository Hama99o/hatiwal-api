# VER-1, daily: delete the ID photos of every verification request decided more
# than VerificationRequest::FILES_KEPT_FOR (90 days) ago. The row stays — the
# decision, the reason and the checklist are what we keep.
class PurgeVerificationFilesJob < ApplicationJob
  queue_as :default

  def perform
    VerificationRequest.purgeable.find_each(&:purge_files!)
  end
end
