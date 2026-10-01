# Which app build each user is on, so a feature that needs a new client can be
# switched on from a number instead of a guess (first need: SUPPORT_ADMIN_INITIATE,
# docs/SUPPORT_MESSAGING.md). Additive, nullable, nothing reads it in a response.
class AddClientVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    # Reported by the app's X-App-Version / X-App-Platform headers (mobile 658b9c6+).
    add_column :users, :last_app_version, :string
    add_column :users, :last_app_platform, :string
    add_column :users, :last_app_version_at, :datetime
    # Last time this user's native app called WITHOUT those headers — i.e. a
    # build older than the one that introduced them (v1.0.4 or earlier).
    add_column :users, :legacy_client_seen_at, :datetime
    add_index :users, :last_app_version_at
    add_index :users, :legacy_client_seen_at
  end
end
