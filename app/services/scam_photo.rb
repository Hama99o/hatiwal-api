# IDEA-5 scam photo detection (1.2.1, hatiwal-mobile docs/design/SCAM_PHOTO.md).
module ScamPhoto
  # Matching needs today's CLIP vectors, so it is on with search by image, unless
  # SCAM_PHOTO_ENABLED=0 (the kill switch: hashes are still written).
  def self.enabled?
    ENV["SCAM_PHOTO_ENABLED"] != "0" && ImageSearch.enabled?
  end
end
