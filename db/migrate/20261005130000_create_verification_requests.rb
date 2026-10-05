# VER-1: an application for the Verified badge, decided by an admin by hand.
# Polymorphic subject so shops (SHOP-1) plug in later; today only User.
# Spec: hatiwal-mobile/docs/VERIFICATION.md.
#
# The ID photos are private Active Storage attachments, purged 90 days after the
# decision (files_purged_at). Only the LAST 4 digits of a document number are
# ever stored.
class CreateVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :verification_requests do |t|
      t.references :subject, polymorphic: true, null: false
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.integer :document_type
      t.string :name_on_document
      t.string :document_last4, limit: 4
      t.string :phone
      t.references :decided_by, foreign_key: { to_table: :admin_users }
      t.datetime :decided_at
      t.string :reason_code
      t.text :reason_text
      t.jsonb :checklist, null: false, default: {}
      t.datetime :files_purged_at
      t.timestamps
    end
    add_index :verification_requests, %i[status created_at]
    # Only one open request per subject at a time.
    add_index :verification_requests, %i[subject_type subject_id],
              unique: true, where: "status = 0", name: "index_verification_requests_one_open_per_subject"
  end
end
