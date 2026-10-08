# Edge pass 1.1.6 (2026-10-08): a PERSONAL listing chat is also pinned to the
# person who sold it. A listing that left Me (into a shop) and came back to Me
# with a different poster (an owner or a manager took it out — Listings::
# MoveService) must start a NEW chat with that poster: the old one stays,
# closed, with the person it was with. Under "one per listing, buyer and
# identity" (shop_id NULL = "the person", whoever that is) the buyer's new chat
# reopened the old thread, so their messages went to the previous poster.
# A shop's chats are unchanged: their seller is the owner and follows a transfer.
class OnePersonalListingChatPerSeller < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  NEW = "index_conversations_one_listing_chat_per_identity_and_seller".freeze
  OLD = "index_conversations_one_listing_chat_per_identity".freeze

  def up
    add_index :conversations, "listing_id, buyer_id, COALESCE(shop_id, 0), (CASE WHEN shop_id IS NULL THEN seller_id ELSE 0 END)",
              unique: true, where: "listing_id IS NOT NULL", name: NEW,
              algorithm: :concurrently, if_not_exists: true
    remove_index :conversations, name: OLD, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :conversations, "listing_id, buyer_id, COALESCE(shop_id, 0)",
              unique: true, where: "listing_id IS NOT NULL", name: OLD,
              algorithm: :concurrently, if_not_exists: true
    remove_index :conversations, name: NEW, algorithm: :concurrently, if_exists: true
  end
end
