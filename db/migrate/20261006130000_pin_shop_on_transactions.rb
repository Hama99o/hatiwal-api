# A shop's reviews are the reviews of sales of THAT shop's products (owner,
# 2026-10-06). The sale's shop is PINNED when the sale (or hold) is recorded,
# like a chat's shop, so a review keeps counting for the shop after the product
# leaves it and never counts for a shop the product joins later. Backfill
# existing rows from the product's shop today (the best record available).
class PinShopOnTransactions < ActiveRecord::Migration[8.1]
  def up
    add_reference :transactions, :shop, foreign_key: { on_delete: :nullify }, index: true
    execute <<~SQL.squish
      UPDATE transactions t
         SET shop_id = l.shop_id
        FROM listings l
       WHERE t.listing_id = l.id
         AND l.shop_id IS NOT NULL
    SQL
  end

  def down
    remove_reference :transactions, :shop, foreign_key: true, index: true
  end
end
