# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 4): Hatiwal Support
# is SEPARATED per identity. A person keeps ONE Support thread (Buyer mode and
# Seller as Me); every shop gets its OWN, read and answered by its team.
#
# A shop's thread is a support conversation with the shop pinned (shop_id), the
# Support account on the buyer side and the shop's owner on the seller side, so
# the team shares it exactly like the shop's chats (Conversation::SELLER_SIDE_SQL).
#
# The 2026-10-07 interim (one mixed thread, each message tagged with
# `context.shop_id`) is unwound: a message written from a shop moves to that
# shop's thread. Idempotent, and a no-op where no shop message exists
# (production: shops are not live yet).
class SupportThreadPerShop < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :conversations, name: "index_conversations_one_support_thread_per_user", if_exists: true
    add_index :conversations, :buyer_id, unique: true, where: "kind = 1 AND shop_id IS NULL",
                                         name: "index_conversations_one_support_thread_per_person", if_not_exists: true
    add_index :conversations, :shop_id, unique: true, where: "kind = 1 AND shop_id IS NOT NULL",
                                        name: "index_conversations_one_support_thread_per_shop", if_not_exists: true

    move_shop_messages_out_of_person_threads
  end

  def down
    remove_index :conversations, name: "index_conversations_one_support_thread_per_shop", if_exists: true
    remove_index :conversations, name: "index_conversations_one_support_thread_per_person", if_exists: true
    add_index :conversations, :buyer_id, unique: true, where: "kind = 1",
                                         name: "index_conversations_one_support_thread_per_user", if_not_exists: true
  end

  private

  def move_shop_messages_out_of_person_threads
    rows = select_rows(<<~SQL.squish)
      SELECT m.id, (m.context->>'shop_id')::bigint, m.conversation_id
        FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
       WHERE c.kind = 1 AND c.shop_id IS NULL AND m.context ? 'shop_id'
    SQL
    return if rows.empty?

    support_id = select_value("SELECT id FROM users WHERE support_account = TRUE LIMIT 1")
    touched = []
    rows.group_by(&:second).each do |shop_id, messages|
      owner_id = select_value("SELECT owner_id FROM shops WHERE id = #{shop_id.to_i}")
      next unless owner_id && support_id

      thread_id = select_value("SELECT id FROM conversations WHERE kind = 1 AND shop_id = #{shop_id.to_i}") ||
                  select_value(<<~SQL.squish)
                    INSERT INTO conversations (kind, shop_id, buyer_id, seller_id, status, created_at, updated_at)
                    VALUES (1, #{shop_id.to_i}, #{support_id.to_i}, #{owner_id.to_i}, 0, NOW(), NOW()) RETURNING id
                  SQL
      ids = messages.map { |m| m.first.to_i }
      execute("UPDATE messages SET conversation_id = #{thread_id.to_i} WHERE id IN (#{ids.join(',')})")
      touched.push(thread_id, *messages.map(&:third))
    end

    touched.uniq.each do |id|
      execute(<<~SQL.squish)
        UPDATE conversations SET last_message_at = (SELECT MAX(created_at) FROM messages WHERE conversation_id = #{id.to_i})
         WHERE id = #{id.to_i}
      SQL
    end
  end
end
