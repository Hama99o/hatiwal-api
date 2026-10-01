# Bulk becomes "bulk message": email and/or in-app (docs/EMAIL.md). A campaign
# records which channels it used and whether push was deliberately chosen;
# in-app recipients get one delivery row each, claimed atomically like email
# rows so a retried run can never post twice. Additive.
class AddInAppToAdminBulkEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_bulk_emails, :via_email, :boolean, null: false, default: true
    add_column :admin_bulk_emails, :via_in_app, :boolean, null: false, default: false
    # A broadcast push lights up every phone at once: OFF unless chosen.
    add_column :admin_bulk_emails, :push, :boolean, null: false, default: false

    create_table :admin_bulk_in_app_deliveries do |t|
      t.references :admin_bulk_email, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :locale
      t.text :body, null: false
      # queued / sent / failed / sending / cancelled / skipped (gate refused at send time)
      t.integer :status, null: false, default: 0
      t.references :message, foreign_key: true
      t.string :push_note
      t.text :error
      t.datetime :sent_at
      t.timestamps
    end
    # The 7-day broadcast cap looks up a user's recent sent deliveries.
    add_index :admin_bulk_in_app_deliveries, %i[user_id sent_at]
  end
end
