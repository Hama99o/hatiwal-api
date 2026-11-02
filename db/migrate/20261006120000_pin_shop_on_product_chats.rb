# A chat's shop is PINNED when it starts (conversations.shop_id), so a chat
# that began on a personal product stays personal if the product later moves
# into a shop (owner rule: staff never see personal chats). Message-shop chats
# already have it; chats about a shop's PRODUCT used to find their shop through
# the listing. Backfill those from the product's shop today — the best record
# of the shop at their start, since a product only changes shop by an explicit
# move.
class PinShopOnProductChats < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE conversations c
         SET shop_id = l.shop_id
        FROM listings l
       WHERE c.listing_id = l.id
         AND c.shop_id IS NULL
         AND l.shop_id IS NOT NULL
         AND c.kind = 0
    SQL
  end

  def down; end
end
