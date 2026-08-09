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

    # Second pass (review fix): also credit sales that predate the
    # transactions table entirely, or were completed via the legacy
    # buyer-less `PUT .../sold` call (never created a Transaction — see
    # Listing#sold_with_buyer!). Without this, a seller whose sales are not
    # represented in `transactions` regresses from the old, always-accurate
    # `u.listings.sold.count` figure straight to 0 on their live public
    # profile. GREATEST (not SUM) because every transaction-tracked sale also
    # flips its listing to `sold`, so summing the two sources would double
    # count. status = 3 is Listing::sold (enum draft/active/reserved/sold).
    execute <<~SQL.squish
      UPDATE users
      SET sold_count = GREATEST(users.sold_count, sub.cnt)
      FROM (
        SELECT user_id, COUNT(*) AS cnt FROM listings WHERE status = 3 GROUP BY user_id
      ) sub
      WHERE users.id = sub.user_id
    SQL

    # bought_count has no listing-based fallback — pre-TX01 sales never
    # recorded which buyer completed them (Listing has no buyer column), so
    # the transactions table is the only possible source of truth here.
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
