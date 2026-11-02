# UPD-1 — "we already told this user to update to <target_version>": the
# guarantee behind "one Support message per user per target version".
class AppUpdateNotice < ApplicationRecord
  belongs_to :user

  validates :platform, inclusion: { in: AppReleaseSetting::PLATFORMS }
  validates :target_version, format: { with: AppVersion::FORMAT }

  # Users on `platform` whose app reported a version below `target` — found
  # from the distinct versions in use (a handful), never a scan of every user.
  def self.old_version_users(platform:, target:)
    on_platform = User.members.where(deleted_at: nil, last_app_platform: platform).where.not(last_app_version: nil)
    old = on_platform.distinct.pluck(:last_app_version).select { |v| AppVersion.below?(v, target) }
    on_platform.where(last_app_version: old)
  end

  # Send the "please update" Support notice to each such user who passes the
  # support gate (Admin::BulkAudience) and has not had one for this target.
  # Returns how many were queued.
  def self.notify_old_versions!(platform:, target:)
    raise ArgumentError, "unknown platform #{platform}" unless AppReleaseSetting::PLATFORMS.include?(platform)
    raise ArgumentError, "not a version: #{target}" unless AppVersion.valid?(target)

    audience = Admin::BulkAudience.new(old_version_users(platform: platform, target: target)).in_app_allowed
    ids = audience.where.not(id: where(target_version: target).select(:user_id)).pluck(:id)
    return 0 if ids.empty?

    now = Time.current
    inserted = insert_all(ids.map { |id| { user_id: id, platform: platform, target_version: target, created_at: now, updated_at: now } },
                          unique_by: %i[user_id target_version], returning: %i[user_id])
    User.where(id: inserted.rows.flatten).find_each { |user| SupportNoticeJob.enqueue(user, :app_update_available) }
    inserted.rows.size
  end
end
