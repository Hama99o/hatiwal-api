# UPD-1 — the force-update / update-reminder settings (one row), and the one
# place that decides an app's status (hatiwal-mobile/docs/FORCE_UPDATE.md).
#
#   below min_version              → "blocked" (full-screen block)
#   below latest_version (≥ min)   → "soft"    (Bazaar banner)
#   otherwise, or unknown version  → "ok"
#
# Safety: a minimum above the newest RELEASED version is refused, so nobody can
# be blocked waiting for a build that does not exist; a missing or malformed
# version from the app is always "ok".
class AppReleaseSetting < ApplicationRecord
  PLATFORMS = ClientVersionReporting::PLATFORMS
  FIELDS = %w[min_version latest_version released_version store_url].freeze
  STATUSES = %w[ok soft blocked].freeze
  # The public store pages (same constants as the web's APP_STORE_URL /
  # GOOGLE_PLAY_URL), used until an admin sets another one.
  DEFAULT_STORE_URLS = {
    "ios" => "https://apps.apple.com/app/hatiwal/id6789510903",
    "android" => "https://play.google.com/store/apps/details?id=com.hatiwal.app"
  }.freeze
  CACHE_KEY = "app_release_settings/v1"
  CACHE_TTL = 60.seconds

  belongs_to :updated_by, class_name: AdminUser.name, optional: true

  # A cleared form field means "not set": nil, never "" (and no stray spaces).
  normalizes(*PLATFORMS.flat_map { |p| FIELDS.map { |f| :"#{p}_#{f}" } }, with: ->(v) { v.to_s.strip.presence })

  PLATFORMS.each do |platform|
    %w[min_version latest_version released_version].each do |field|
      validates :"#{platform}_#{field}", format: { with: AppVersion::FORMAT }, allow_blank: true
    end
    validates :"#{platform}_store_url", format: { with: %r{\Ahttps://\S+\z} }, allow_blank: true
  end
  validate :versions_are_released

  after_commit :clear_cache

  def self.current
    first || create!
  end

  # The settings as plain data, from Rails.cache — one row for every app at
  # 100k users, no per-user query.
  def self.cached_values
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { current.values }
  end

  # What GET /app_config answers for one app.
  def self.config_for(platform:, version:)
    values = cached_values
    platform = platform.to_s.downcase
    platform = nil unless PLATFORMS.include?(platform)
    settings = platform ? values.fetch(platform) : {}
    {
      platform: platform,
      min_version: settings["min_version"],
      latest_version: settings["latest_version"],
      store_url: settings["store_url"],
      status: status(version, settings)
    }
  end

  def self.status(version, settings)
    return "ok" unless AppVersion.valid?(version)
    return "blocked" if settings["min_version"].present? && AppVersion.below?(version, settings["min_version"])
    return "soft" if settings["latest_version"].present? && AppVersion.below?(version, settings["latest_version"])

    "ok"
  end

  # { "ios" => { "min_version" => …, … }, "android" => { … } } — strings only,
  # so it caches safely.
  def values
    PLATFORMS.index_with do |platform|
      FIELDS.index_with { |field| public_send(:"#{platform}_#{field}").presence }
            .tap { |h| h["store_url"] ||= DEFAULT_STORE_URLS[platform] }
    end
  end

  # The platforms whose minimum this change RAISES (the admin form confirms them).
  def raised_minimums
    PLATFORMS.select do |platform|
      old_min, new_min = attribute_change_to_be_saved(:"#{platform}_min_version")
      new_min.present? && (old_min.blank? || AppVersion.below?(old_min, new_min))
    end
  end

  private

  def versions_are_released
    PLATFORMS.each do |platform|
      released = public_send(:"#{platform}_released_version")
      %w[min_version latest_version].each do |field|
        value = public_send(:"#{platform}_#{field}")
        next if value.blank? || !AppVersion.valid?(value)

        if released.blank? || AppVersion.below?(released, value)
          errors.add(:"#{platform}_#{field}", :not_released, version: value, platform: platform == "ios" ? "iOS" : "Android")
        end
      end
    end
  end

  def clear_cache
    Rails.cache.delete(CACHE_KEY)
  end
end
