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

  NEW_COLUMNS = "listing_id, buyer_id, COALESCE(shop_id, 0), (CASE WHEN shop_id IS NULL THEN seller_id ELSE 0 END)".freeze
  OLD_COLUMNS = "listing_id, buyer_id, COALESCE(shop_id, 0)".freeze

  # Safe to re-run after a failed concurrent build (review 2026-10-08, dd): a
  # CREATE INDEX CONCURRENTLY that fails leaves an INVALID index behind, which
  # `if_not_exists` would have taken for done — and the old index was then
  # dropped, leaving NO unique index. So: drop an invalid leftover, build, and
  # drop the old index only once the new one is VALID.
  def up
    replace_index(build: NEW, columns: NEW_COLUMNS, drop: OLD)
  end

  # Truly reversible only while the data allows the old rule. Once a listing has
  # two personal chats with the same buyer but different sellers (which is what
  # `up` makes possible), the old unique index cannot be built: refuse before
  # touching anything, rather than fail mid-way and leave an INVALID index.
  def down
    if duplicate_personal_chats?
      raise ActiveRecord::IrreversibleMigration,
            "personal listing chats now differ only by seller; the old one-per-listing-and-buyer index cannot be rebuilt"
    end

    replace_index(build: OLD, columns: OLD_COLUMNS, drop: NEW)
  end

  private

  def replace_index(build:, columns:, drop:)
    remove_index :conversations, name: build, algorithm: :concurrently if index_state(build) == :invalid
    unless index_state(build) == :valid
      add_index :conversations, columns, unique: true, where: "listing_id IS NOT NULL", name: build, algorithm: :concurrently
    end
    raise "#{build} is not valid after building it; #{drop} was left in place" unless index_state(build) == :valid

    remove_index :conversations, name: drop, algorithm: :concurrently, if_exists: true
  end

  # :valid, :invalid, or nil when there is no such index.
  def index_state(name)
    valid = select_value(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
       WHERE c.relname = #{connection.quote(name)}
    SQL
    return nil if valid.nil?

    valid ? :valid : :invalid
  end

  def duplicate_personal_chats?
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM conversations WHERE listing_id IS NOT NULL
       GROUP BY listing_id, buyer_id, COALESCE(shop_id, 0) HAVING count(*) > 1 LIMIT 1
    SQL
  end
end
