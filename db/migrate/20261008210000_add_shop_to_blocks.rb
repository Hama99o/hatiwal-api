# privacy-b (2026-10-08): a block made from a shop (POST /shops/:id/block) still
# blocks the owner underneath — every block check stays as it is — but
# remembers the shop, so the blocker's list shows the SHOP, never the person.
class AddShopToBlocks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :blocks, :shop, null: true, index: { algorithm: :concurrently }
  end
end
