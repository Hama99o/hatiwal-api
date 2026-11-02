# Owner, 2026-10-07: one Support thread per person, written from any mode or
# shop. Each user message in it records WHERE it was written from
# ({mode: buyer|seller, shop_id?, role?}) so the admin can tell. Nullable: older
# apps send none ("unknown").
class AddContextToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :context, :jsonb
  end
end
