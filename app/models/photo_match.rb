# IDEA-5 scam photo detection (1.2.1, hatiwal-mobile docs/design/SCAM_PHOTO.md): two listings of
# DIFFERENT accounts that share a photo, found by ScamPhoto::Matcher. `listing` is the newer one
# (its Flag, source reused_photo, is `flag`); `matched_listing` the older, likely original.
#
# One row per pair. A dismissed pair is never flagged again; the admin's decision on the flag
# sets the status (ProhibitedItems::Moderation). Nothing here ever changes either listing.
class PhotoMatch < ApplicationRecord
  belongs_to :listing, class_name: Listing.name
  belongs_to :matched_listing, class_name: Listing.name
  belongs_to :attachment, class_name: ActiveStorage::Attachment.name, optional: true
  belongs_to :matched_attachment, class_name: ActiveStorage::Attachment.name, optional: true
  belongs_to :flag, class_name: Flag.name, optional: true

  enum :status, { open: 0, dismissed: 1, actioned: 2 }

  validates :cosine, :hash_distance, presence: true
end
