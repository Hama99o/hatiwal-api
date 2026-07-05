class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :seller,  null: false, foreign_key: { to_table: :users }
      t.references :buyer,   null: false, foreign_key: { to_table: :users }
      t.decimal :final_price, null: false, precision: 12, scale: 2
      t.string  :currency,    null: false, default: "AFN"
      t.integer :status,      null: false, default: 0
      t.datetime :completed_at

      t.timestamps
    end

    # Only one OPEN (reserved) transaction may exist per listing at a time —
    # a partial unique index (status 0 = reserved). A listing can accumulate
    # multiple *sold* transaction rows over its lifetime (e.g. relisted after
    # a prior sale), so uniqueness only applies while a deal is still open.
    add_index :transactions, :listing_id, unique: true, where: "status = 0",
                                           name: "index_transactions_on_listing_id_while_open"
    add_index :transactions, :status
  end
end
