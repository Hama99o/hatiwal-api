class AllowNullBuyerOnTransactions < ActiveRecord::Migration[8.1]
  # SF-B3 — "sold to someone not on Hatiwal" must leave a ledger row.
  #
  # Until now that sale recorded NOTHING: Listing#sold_with_buyer! saw
  # `clear_buyer: true`, cancelled any open reservation and returned nil, so
  # `sold_units` moved but no Transaction existed. Two consequences, both real:
  #
  #   1. The seller could never see the sale again — GET /my/transactions had no
  #      row to return, and the "who bought how many" ledger silently skipped it.
  #   2. SF-B4's correction endpoint has nothing to point at. You cannot undo a
  #      sale that was never written down.
  #
  # The model's nil-safety was already written and waiting — both
  # `buyer_is_not_seller` and `buyer_is_conversation_participant` open with
  # `return if buyer_id.blank?`. Only the DB NOT NULL (and the implicitly-required
  # `belongs_to :buyer`) stood in the way.
  #
  # REVERSIBLE ONLY WHILE NO BUYER-LESS ROW EXISTS: rolling back re-imposes NOT
  # NULL, which fails if an outside-buyer sale has since been recorded. That is
  # the honest state of affairs — say it here rather than let a rollback surprise
  # someone — and it is why this is a `change_column_null` and not a data change.
  def up
    change_column_null :transactions, :buyer_id, true
  end

  def down
    change_column_null :transactions, :buyer_id, false
  end
end
