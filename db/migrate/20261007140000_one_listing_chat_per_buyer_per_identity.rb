# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5):
# moving a listing to another shop does NOT move its chats. The old chat stays
# with the identity it started with (conversations.shop_id, pinned), and the
# buyer starts a NEW one with the listing's new seller. So "one chat per listing
# and buyer" becomes "one per listing, buyer and selling identity"
# (shop_id NULL = the person). Listing chats only: Support threads (no listing)
# keep their own one-per-person / one-per-shop indexes.
class OneListingChatPerBuyerPerIdentity < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  NEW = "index_conversations_one_listing_chat_per_identity".freeze
  OLD = "index_conversations_on_listing_id_and_buyer_id".freeze

  def up
    add_index :conversations, "listing_id, buyer_id, COALESCE(shop_id, 0)",
              unique: true, where: "listing_id IS NOT NULL", name: NEW,
              algorithm: :concurrently, if_not_exists: true
    remove_index :conversations, name: OLD, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :conversations, %i[listing_id buyer_id], unique: true, name: OLD,
                                                       algorithm: :concurrently, if_not_exists: true
    remove_index :conversations, name: NEW, algorithm: :concurrently, if_exists: true
  end
end
