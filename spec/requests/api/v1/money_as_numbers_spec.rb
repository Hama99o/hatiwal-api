require "rails_helper"

# P0 (2026-10-27): money is a JSON NUMBER on every endpoint the apps read.
#
# A numeric column is a BigDecimal and was serialized as a STRING
# ("price": "560000.0"). Mobile 1.1.7+ formats only real numbers, so every
# listing price rendered blank in the live app. The specs that already looked
# at prices compared `.to_f`, which accepts a string — so this went unseen.
# Here each money field must be an actual Numeric, and still carry its value.
RSpec.describe "Money fields are JSON numbers", type: :request do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:listing) { create(:listing, :active, user: seller, price: 560_000) }

  def json = JSON.parse(response.body)

  def expect_money(value, amount)
    expect(value).to be_a(Numeric), "expected a JSON number, got #{value.inspect} (#{value.class})"
    expect(value).to eq(amount)
  end

  it "GET /listings — listings[].price" do
    listing
    get "/api/v1/listings", as: :json
    row = json["listings"].find { |l| l["id"] == listing.id }
    expect_money(row["price"], 560_000)
  end

  it "GET /listings/:id — listing.price" do
    get "/api/v1/listings/#{listing.id}", as: :json
    expect_money(json["listing"]["price"], 560_000)
  end

  it "GET /my/listings/:id — the hold's final_price (listing.sale.final_price)" do
    create(:transaction, listing: listing, seller: seller, buyer: buyer, final_price: 545_000)
    get "/api/v1/my/listings/#{listing.id}", headers: auth_headers_for(seller), as: :json
    sale = json["listing"]["sale"]
    expect(sale).to be_present
    expect_money(sale["final_price"], 545_000)
  end

  it "GET /my/saved_listings — price, price_at_save and price_drop_amount" do
    create(:saved_listing, user: buyer, listing: listing) # snapshots 560,000
    listing.update!(price: 500_000)
    get "/api/v1/my/saved_listings", headers: auth_headers_for(buyer), as: :json
    row = json["listings"].find { |l| l["id"] == listing.id }
    expect_money(row["price"], 500_000)
    expect_money(row["price_at_save"], 560_000)
    expect_money(row["price_drop_amount"], 60_000)
  end

  it "GET /my/transactions — final_price and the nested listing.price" do
    create(:conversation, listing: listing, seller: seller, buyer: buyer)
    create(:transaction, listing: listing, seller: seller, buyer: buyer, final_price: 545_000)
    get "/api/v1/my/transactions", headers: auth_headers_for(seller), as: :json
    txn = json["transactions"].first
    expect_money(txn["final_price"], 545_000)
    expect_money(txn["listing"]["price"], 560_000)
  end

  it "GET /conversations and /conversations/:id — the listing's price" do
    convo = create(:conversation, listing: listing, seller: seller, buyer: buyer)
    create(:message, conversation: convo, user: buyer, body: "Is it still available?")

    get "/api/v1/conversations", headers: auth_headers_for(buyer), as: :json
    row = json["conversations"].find { |c| c["id"] == convo.id }
    expect_money(row["listing"]["price"], 560_000)

    get "/api/v1/conversations/#{convo.id}", headers: auth_headers_for(buyer), as: :json
    expect_money(json["conversation"]["listing"]["price"], 560_000)
  end

  it "keeps cents (scale 2) — 1499.5 stays 1499.5" do
    cents = create(:listing, :active, user: seller, price: BigDecimal("1499.50"))
    get "/api/v1/listings/#{cents.id}", as: :json
    expect_money(json["listing"]["price"], 1499.5)
  end
end
