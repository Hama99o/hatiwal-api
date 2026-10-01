# Bulk email: one campaign (the segment, the per-language content, the state of
# the run) and one admin_emails row per recipient, SNAPSHOT at confirm time —
# so what the admin approved is exactly what sends, and stop/resume have rows
# to stand on (docs/EMAIL.md). Additive.
class CreateAdminBulkEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_bulk_emails do |t|
      t.references :admin_user, null: false, foreign_key: true
      # The segment in words ("Status: active · City: Kabul") and the exact
      # filter params, so the history says who it went to.
      t.string :segment
      t.jsonb :filter_params, null: false, default: {}
      # { "en" => { "subject" => …, "body" => … }, "ps" => {…}, … }
      t.jsonb :content, null: false, default: {}
      t.string :fallback_locale, null: false, default: "en"
      t.integer :status, null: false, default: 0
      t.integer :recipients_count, null: false, default: 0
      t.datetime :finished_at
      t.timestamps
    end

    add_reference :admin_emails, :admin_bulk_email, foreign_key: true
    # Which language version this recipient got.
    add_column :admin_emails, :locale, :string
  end
end
