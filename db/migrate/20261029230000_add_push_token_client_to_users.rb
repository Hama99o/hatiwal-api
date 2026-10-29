# The devise client (device session) that registered `push_token`. A sign-out clears the token only when
# that client signs out — a sign-out on the web or another phone used to wipe the phone's token (QA B11 E,
# 2026-10-29). NULL for tokens registered before this column: they keep the old rule (cleared on a sign-out).
class AddPushTokenClientToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :push_token_client, :string
  end
end
