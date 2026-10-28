# Privacy review 2026-10-28: a single-use, 60-second pass for the chat's live
# connection, for clients that cannot set WebSocket headers (hatiwal-web). Only
# the ticket's SHA-256 digest is stored; the row goes when it is used, and a
# daily job removes the ones never used.
class CreateCableTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :cable_tickets do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :digest, null: false, limit: 64
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :cable_tickets, :digest, unique: true
    add_index :cable_tickets, :expires_at
  end
end
