# privacy-b (2026-10-08): who may see the user id behind a shop's face. Any id
# opens the guest-readable public profile (name, photo), so a buyer on a 1.1.6+
# client gets null + the shop's own id; the shop's team (its own-listing and
# seller-side checks) and clients older than 1.1.6 (Current.legacy_shop_ids)
# keep the owner's id.
module ShopFace
  NEW_CLIENT_VERSION = Gem::Version.new("1.1.6")

  def self.owner_id_for(shop)
    return shop.owner_id if Current.legacy_shop_ids || Current.viewer_shop_ids.include?(shop.id)

    nil
  end

  # 1.1.6+ apps send X-App-Version; the web sends X-App-Platform: web. Anything
  # else (no header: every store build before 2026-10-01) is legacy.
  def self.legacy_client?(platform:, version:)
    return false if platform.to_s == "web"
    return true unless version.present? && Gem::Version.correct?(version.to_s)

    Gem::Version.new(version.to_s) < NEW_CLIENT_VERSION
  end
end
