# Sign in with Apple (1.1.7): the Apple account id (`sub`, stable per app team)
# and the refresh token Apple issues for the authorization code, kept only so
# the account's Apple authorization can be REVOKED when it is deleted (App
# Store guideline 5.1.1(v)). The token column is encrypted (User#encrypts).
class AddAppleSignInToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :apple_uid, :string
    add_column :users, :apple_refresh_token, :text
    add_index :users, :apple_uid, unique: true
  end
end
