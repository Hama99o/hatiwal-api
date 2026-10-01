# Why this user's app could NOT register for push, as reported by the app
# ("<stage>: <message>"). The last one only, overwritten — a history table
# would be a log nobody reads, which is how Android's missing Firebase stayed
# invisible for months (docs/PUSH_NOTIFICATIONS.md). Additive: v1.0.4 never
# sends it.
class AddPushRegistrationErrorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :push_registration_error, :string, limit: 300
    add_column :users, :push_registration_error_at, :datetime
  end
end
