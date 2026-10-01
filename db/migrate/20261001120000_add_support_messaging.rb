# Support messaging: a user ⇄ Hatiwal Support thread, carried by the existing
# Conversation/Message tables so every client endpoint keeps working.
#
# ADDITIVE ONLY, and deliberately creates NO support conversation. v1.0.4 of the
# app is live and sends no version header, so anything the API returns is
# returned to it too. Every existing conversation takes the column default
# (`listing`), so no old client ever receives a support thread from this
# migration. See docs/SUPPORT_MESSAGING.md before backfilling anything here.
class AddSupportMessaging < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :kind, :integer, default: 0, null: false
    # One support thread per user (kind 1 = support).
    add_index :conversations, :buyer_id, unique: true, where: "kind = 1",
              name: "index_conversations_one_support_thread_per_user"

    add_column :users, :support_account, :boolean, default: false, null: false
    # Exactly one Support account.
    add_index :users, :support_account, unique: true, where: "support_account",
              name: "index_users_single_support_account"

    # Which admin wrote a reply posted as the Support account. Audit only;
    # never serialized to clients.
    add_reference :messages, :admin_user, foreign_key: true, null: true
  end
end
