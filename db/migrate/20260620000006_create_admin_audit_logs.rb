class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_logs do |t|
      # The admin who performed the action. Nullable so the log survives if the
      # admin account is later removed.
      t.references :admin_user, null: true, foreign_key: true
      t.string  :action, null: false
      # Polymorphic subject of the action (a User, Listing, Report, …).
      t.string  :target_type
      t.bigint  :target_id
      t.string  :details

      t.datetime :created_at, null: false
    end

    add_index :admin_audit_logs, [ :target_type, :target_id ]
    add_index :admin_audit_logs, :created_at
  end
end
