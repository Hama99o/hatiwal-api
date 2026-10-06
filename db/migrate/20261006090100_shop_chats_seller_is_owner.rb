# SHOP-3 — a shop product chat's seller is the shop OWNER, whoever posted the
# product (docs/SHOPS.md). Today every shop product was posted by its owner, so
# this updates nothing; it makes the rule hold for data written before it.
class ShopChatsSellerIsOwner < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE conversations c
         SET seller_id = s.owner_id
        FROM listings l
        JOIN shops s ON s.id = l.shop_id
       WHERE c.listing_id = l.id
         AND c.seller_id <> s.owner_id
         AND c.buyer_id <> s.owner_id
    SQL
  end

  def down; end
end
