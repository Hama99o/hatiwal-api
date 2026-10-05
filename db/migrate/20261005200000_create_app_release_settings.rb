# UPD-1 — force update (hard) and update reminder (soft), editable in admin
# without a deploy (hatiwal-mobile/docs/FORCE_UPDATE.md). One row; per-platform
# columns. Versions are dotted numbers ("1.1.5"); blank = not set.
class CreateAppReleaseSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :app_release_settings do |t|
      %w[ios android].each do |platform|
        t.string :"#{platform}_min_version"
        t.string :"#{platform}_latest_version"
        t.string :"#{platform}_released_version"
        t.string :"#{platform}_store_url"
      end
      t.references :updated_by, foreign_key: { to_table: :admin_users }
      t.timestamps
    end

    # "Message users on old versions": one Support notice per user per target
    # version, never two.
    create_table :app_update_notices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :target_version, null: false
      t.timestamps
    end
    add_index :app_update_notices, %i[user_id target_version], unique: true
  end
end
