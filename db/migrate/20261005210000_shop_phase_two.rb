# SHOP-2 (hatiwal-mobile/docs/SHOPS.md, "Phase 2 — definition of done"):
# several shops per owner, and chats with a shop that have no product.
class ShopPhaseTwo < ActiveRecord::Migration[8.1]
  def change
    # Phase 1 allowed one open shop per owner; phase 2 lifts it (the duplicate
    # rule lives on Shop and is serialized by a per-owner advisory lock).
    remove_index :shops, :owner_id, name: "index_shops_one_open_per_owner", unique: true, where: "(status <> 3)"

    # A "Message shop" chat from the shop page: no listing, the shop instead.
    add_reference :conversations, :shop, null: true, foreign_key: { on_delete: :nullify }, index: true
    add_index :conversations, %i[buyer_id shop_id], unique: true, where: "listing_id IS NULL AND shop_id IS NOT NULL",
                                                   name: "index_conversations_one_shop_chat_per_buyer"
  end
end
