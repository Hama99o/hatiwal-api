class AddOfferQuantityToMessages < ActiveRecord::Migration[8.1]
  # SF-B11 — an offer gains an optional quantity.
  #
  # THE GAP THIS CLOSES, named by the spike that shipped without it
  # (docs/SPIKE_LISTING_QUANTITY.md §13.4, "An offer carries no quantity"):
  # `messages` stores an offer as an amount only, so on a 15-bag listing nothing
  # downstream can tell whether "I offer 12,000" meant one bag or the lot. A
  # buyer's stated quantity reaches the seller as PROSE and nothing else — SF-M6
  # writes "3 × AFN 14,000 = AFN 42,000" into the opening message and says so in
  # its own header ("the quantity is never persisted as structured data
  # anywhere") — so when the seller marks it sold, `units_for_sale` defaults a
  # batch to ONE unit and the seller has to remember and re-type 3. If they
  # don't, stock reads 14 where it should read 12 and the listing starts lying to
  # the next buyer: exactly the spike's own top risk ("a stale number lies to
  # buyers"), arriving through a different door.
  #
  # An offer is the right carrier because it is the moment the two people agree
  # terms. Once it holds a quantity, mark-sold prefills from the accepted offer
  # and the number stops depending on human memory.
  #
  # NULLABLE, AND DELIBERATELY NOT DEFAULTED TO 1. "Absent" and "one" are
  # different facts: absent means the sender said nothing about how many (every
  # offer that exists today, and every offer on a single-item listing), one means
  # they said one. A default of 1 would erase that distinction permanently and
  # for every historical row, and it is the distinction a client needs to decide
  # whether to show an agreed quantity at all. `nil` is read as one unit by
  # every client; nothing existing changes.
  #
  # `hatiwal-web` consumes the same API and is still on the pre-redesign sell
  # flow (card 285). A nullable additive column changes no existing field's
  # meaning, so web keeps behaving exactly as it does today.
  def change
    add_column :messages, :offer_quantity, :integer, null: true

    # The application floor is `greater_than: 0` (Message#offer_quantity
    # numericality). This is the backstop for everything that bypasses
    # validation — update_column, raw SQL, Administrate — written the same way
    # and for the same reason as `listings_quantity_positive`. `IS NULL OR` is
    # what keeps "unspecified" legal.
    add_check_constraint :messages,
                         "offer_quantity IS NULL OR offer_quantity >= 1",
                         name: "messages_offer_quantity_positive"
  end
end
