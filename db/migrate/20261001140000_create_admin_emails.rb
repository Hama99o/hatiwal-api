# One row per email an admin writes to one user (docs/EMAIL.md). Email can't be
# unsent, so every send is recorded with who wrote it, what it said, and whether
# it actually went out — a failure is visible instead of vanishing.
class CreateAdminEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_emails do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :subject, null: false
      t.text :body, null: false
      t.integer :status, null: false, default: 0
      t.text :error
      t.datetime :sent_at
      t.timestamps
    end
  end
end
