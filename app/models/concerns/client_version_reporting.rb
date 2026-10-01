# Which app build a user is on.
#
# The mobile app sends X-App-Version / X-App-Platform on every request from
# 658b9c6 on. Builds before that (v1.0.4 and older) send nothing, which is why
# the API has never been able to gate a feature on client version. This records
# both cases:
#
#   last_app_version / _platform / _at  — the newest build that REPORTED itself
#   legacy_client_seen_at               — the native app called WITHOUT headers
#
# so "how many active users are still on v1.0.4?" is
# `User.on_legacy_client_since(30.days.ago).count`, a number rather than a
# guess. That is the readout to check before switching on anything an old build
# can't render (first: SUPPORT_ADMIN_INITIATE).
#
# A headerless request only counts as legacy when its User-Agent is a native
# mobile HTTP stack. hatiwal-web calls the same API from Node without these
# headers, and must not be counted as an old phone.
module ClientVersionReporting
  extend ActiveSupport::Concern

  PLATFORMS = %w[ios android].freeze
  # app.json versions are dotted numbers ("1.1.0"). Anything else is ignored
  # rather than stored, so a garbage header can't pollute the readout.
  VERSION_FORMAT = /\A\d{1,4}(\.\d{1,4}){0,3}\z/
  # React Native's networking: OkHttp on Android, CFNetwork/Darwin on iOS.
  NATIVE_USER_AGENT = /okhttp|CFNetwork|Darwin/i
  # Rewrite at most this often per user when nothing changed — this runs on
  # every authenticated request and must not become a write per request.
  WRITE_INTERVAL = 1.hour

  included do
    scope :on_legacy_client_since, ->(time) { where(legacy_client_seen_at: time..) }
    scope :reported_version_since, ->(time) { where(last_app_version_at: time..) }
  end

  # Never raises: a bad header must not fail the request it rode in on.
  def record_client!(version:, platform:, user_agent:, now: Time.current)
    version  = version.to_s.strip
    platform = platform.to_s.strip.downcase

    if version.match?(VERSION_FORMAT)
      record_reported_client(version, PLATFORMS.include?(platform) ? platform : nil, now)
    elsif version.empty? && user_agent.to_s.match?(NATIVE_USER_AGENT)
      record_legacy_client(now)
    end
  end

  private

  def record_reported_client(version, platform, now)
    unchanged = last_app_version == version && last_app_platform == platform
    return if unchanged && last_app_version_at&.after?(now - WRITE_INTERVAL)

    update_columns(last_app_version: version, last_app_platform: platform, last_app_version_at: now)
  end

  def record_legacy_client(now)
    return if legacy_client_seen_at&.after?(now - WRITE_INTERVAL)

    update_columns(legacy_client_seen_at: now)
  end
end
