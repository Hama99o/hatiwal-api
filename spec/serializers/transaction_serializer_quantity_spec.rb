require "rails_helper"

# "Who bought how many" — docs/SPIKE_LISTING_QUANTITY.md §0b.
#
# `transactions.quantity` is written by every sale, but until it was on the wire
# no client could read it: the sales ledger the owner asked for ("save info who
# bought how much") was recorded and then invisible. This spec keeps it on the
# wire, and keeps the meaning of `final_price` pinned alongside it, because the
# two are only unambiguous together.
RSpec.describe TransactionSerializer, "quantity" do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }

  def sell!(listing_quantity:, units:, price: 13_000)
    listing = create(:listing, user: seller, status: :active, quantity: listing_quantity)
    create(:conversation, listing: listing, buyer: buyer)
    listing.sold_with_buyer!(buyer_id: buyer.id, quantity: units, final_price: price)
  end

  def payload(txn, **opts)
    JSON.parse(described_class.render(txn, **opts))
  end

  it "reports how many units the deal covered" do
    txn = sell!(listing_quantity: 15, units: 3)
    expect(payload(txn)["quantity"]).to eq(3)
  end

  it "reports 1 for a single-item sale, so the majority case is unchanged" do
    txn = sell!(listing_quantity: 1, units: 1)
    expect(payload(txn)["quantity"]).to eq(1)
  end

  # final_price is PER UNIT on a multi-unit sale — the seller types it into a
  # field placeholder-seeded with the listing's own per-unit price and captioned
  # "the price for one item". A client that read it as the deal total would show
  # 13,000 for a 39,000 sale, in the record a review is later attached to.
  it "keeps final_price per-unit, not multiplied by the quantity" do
    txn = sell!(listing_quantity: 15, units: 3, price: 13_000)
    expect(payload(txn)["final_price"].to_f).to eq(13_000.0)
    expect(payload(txn)["quantity"]).to eq(3)
  end

  it "carries the listing's own stock flags, so a sales row can say 'each'" do
    txn = sell!(listing_quantity: 15, units: 3)
    listing = payload(txn)["listing"]
    expect(listing["multi_unit"]).to be(true)
    # 3 taken by this sale; `record_units_sold!` is the controller's job, so the
    # remainder here is still 15 — what matters is that the field is present and
    # reads from the listing, not from the transaction.
    expect(listing).to have_key("available_units")
  end

  it "reports multi_unit false on a single-item listing" do
    txn = sell!(listing_quantity: 1, units: 1)
    expect(payload(txn)["listing"]["multi_unit"]).to be(false)
  end
end
