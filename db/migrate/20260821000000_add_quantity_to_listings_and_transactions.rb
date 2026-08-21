class AddQuantityToListingsAndTransactions < ActiveRecord::Migration[8.1]
  # Multi-quantity listings — Tier 1 of docs/SPIKE_LISTING_QUANTITY.md.
  #
  # A seller with 15 identical bags could not say so, and a buyer who wanted 15
  # had no way to know there was more than one. This adds the count, and the
  # ledger entry for "who bought how many".
  #
  # ADDITIVE BY DESIGN. Every column defaults to the single-unit case, so every
  # existing listing and transaction keeps behaving exactly as it does today and
  # `status` keeps its current meaning when quantity == 1. That constraint is what
  # keeps this a one-cycle change instead of a rewrite of 686 status references
  # across the clients (see the spike, §4 and §10).
  def change
    # Total units the seller has. 1 for everything that exists today.
    add_column :listings, :quantity, :integer, null: false, default: 1
    # Units already sold, denormalized. Derived from the transactions ledger, but
    # stored because the browse feed reads it per row and a SUM per listing would
    # be an N+1 across the whole feed — the same reason users.sold_count exists.
    # Named `sold_units` and not `sold_count` deliberately: `users.sold_count` is
    # the seller's lifetime trust counter and confusing the two would be easy.
    add_column :listings, :sold_units, :integer, null: false, default: 0

    # How many units this one sale covered. A buyer taking 3 of 15 is ONE deal:
    # one transaction, one review, one entry in the seller's trust count.
    add_column :transactions, :quantity, :integer, null: false, default: 1

    add_check_constraint :listings, "quantity >= 1", name: "listings_quantity_positive"
    add_check_constraint :transactions, "quantity >= 1", name: "transactions_quantity_positive"

    # The one invariant that must never be violated: a listing cannot have sold
    # more units than it has. Enforced by the DATABASE, not the application —
    # overselling is the failure that puts two buyers at the same meetup expecting
    # the same goods, and application code is the thing that gets edited.
    add_check_constraint :listings,
                         "sold_units >= 0 AND sold_units <= quantity",
                         name: "listings_sold_units_within_quantity"
  end
end
