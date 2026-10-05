# VER-1, owner decision 2026-10-05: keep the FULL document number, encrypted
# (Active Record Encryption, non-deterministic), plus an HMAC digest to find the
# same ID on another account without decrypting anything. document_last4 stays
# for display. Spec: hatiwal-mobile/docs/VERIFICATION.md "ID number".
class AddDocumentNumberToVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :verification_requests, :document_number, :text
    add_column :verification_requests, :document_number_digest, :string
    add_index :verification_requests, :document_number_digest
  end
end
