# Owner, 2026-10-07: a person's Profile is personal. sold_count, avg_rating and
# review_count leave out sales made as a shop (transactions.shop_id), which count
# on the shop. Recompute them for every seller who has a shop sale. Idempotent
# (a recompute from source); a no-op where no shop sale exists yet (production).
class PersonalTrustStatsExcludeShopSales < ActiveRecord::Migration[8.1]
  def up
    seller_ids = select_values("SELECT DISTINCT seller_id FROM transactions WHERE shop_id IS NOT NULL")
    User.where(id: seller_ids).find_each do |user|
      user.recompute_transaction_counters!
      user.recompute_review_stats!
    end
  end

  def down; end
end
