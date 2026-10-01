# One row per thing an admin SENT to one person, whatever the channel(s) — the
# unit of the Messages history ("see how send"). Email delivery is still
# recorded per email in admin_emails; an in-app message is a Message in the
# user's support thread. This row ties them to the one action that sent them.
class CreateAdminOutreaches < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_outreaches do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :via_email, null: false, default: false
      t.boolean :via_in_app, null: false, default: false
      t.string :subject
      t.text :body, null: false
      t.references :admin_email, foreign_key: true
      t.references :message, foreign_key: true
      # Whether a push could even be attempted for the in-app message, as known
      # at send time ("push queued" / "no push token: <app-reported reason>").
      t.string :push_note
      # compose (Messages screen) or support_inbox (a reply inside a thread).
      t.integer :source, null: false, default: 0
      # The user had opted out of bulk email and the admin sent anyway, knowingly
      # (a one-to-one email about their account is not marketing).
      t.boolean :opt_out_acknowledged, null: false, default: false
      t.timestamps
    end
    add_index :admin_outreaches, :created_at

    # Opted out of BULK email (unsubscribe link). Excluded from every bulk send;
    # shown as a warning on one-to-one email.
    add_column :users, :email_opt_out_at, :datetime
  end
end
