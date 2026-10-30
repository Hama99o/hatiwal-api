# IDEA-9: chunked uploads that got no chunk for ResumableUpload::STALE_AFTER (24 h) are given up: the row and its
# part go, so a phone that never came back does not keep disk. Completed ones are only rows (their part is gone).
class ResumableUploadSweepJob < ApplicationJob
  queue_as :default

  def perform
    ResumableUpload.stale.find_each do |upload|
      upload.delete_part
      upload.destroy
    end
  end
end
