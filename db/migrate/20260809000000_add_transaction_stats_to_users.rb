class AddTransactionStatsToUsers < ActiveRecord::Migration[8.1]
  # Denormalized counters over the `transactions` table (TASK-TX01), so the
  # public profile trust dossier + listing detail seller card + own profile
  # stats row never run a live COUNT query per request (mirrors the
  # avg_rating/review_count counter-cache pattern added for reviews). Bumped
  # atomically by Transaction#bump_trust_counters! the moment a transaction
  # first becomes `sold` (see app/models/transaction.rb) — never decremented,
  # since there is currently no "unsell" flow.
  def up
    add_column :users, :sold_count, :integer, null: false, default: 0
    add_column :users, :bought_count, :integer, null: false, default: 0

    # Backfill for any `sold` transactions created before these counters
    # existed (TX01 already shipped, so sold rows may already be present).
    # status = 1 is Transaction::sold (enum reserved: 0, sold: 1).
    execute <<~SQL.squish
      UPDATE users
      SET sold_count = sub.cnt
      FROM (
        SELECT seller_id, COUNT(*) AS cnt FROM transactions WHERE status = 1 GROUP BY seller_id
      ) sub
      WHERE users.id = sub.seller_id
    SQL

    execute <<~SQL.squish
      UPDATE users
      SET bought_count = sub.cnt
      FROM (
        SELECT buyer_id, COUNT(*) AS cnt FROM transactions WHERE status = 1 GROUP BY buyer_id
      ) sub
      WHERE users.id = sub.buyer_id
    SQL
  end

  def down
    remove_column :users, :sold_count
    remove_column :users, :bought_count
  end
end
