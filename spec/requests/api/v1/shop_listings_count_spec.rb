require "rails_helper"

# The shop page's "Products (n)" follows the same rule as the list under it
# (GET /listings?shop_id=): a blocked pair still sees the page, but its count
# must not give the block away (SHOPS.md "The shop page", decided 2026-10-06).
RSpec.describe "Shop listings_count as the viewer sees it", type: :request do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let!(:products) { create_list(:listing, 3, :active, user: owner, shop: shop) }
  let(:buyer) { create(:user) }
  let(:blocked) { create(:user) }

  def count_for(user)
    get "/api/v1/shops/#{shop.id}", headers: user ? auth_headers_for(user) : {}
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)["shop"]["listings_count"]
  end

  def feed_count_for(user)
    get "/api/v1/listings", params: { shop_id: shop.id }, headers: user ? auth_headers_for(user) : {}
    JSON.parse(response.body)["listings"].size
  end

  it "a guest and another buyer get the full count" do
    expect(count_for(nil)).to eq(3)
    expect(count_for(buyer)).to eq(3)
  end

  it "a blocked pair gets 0 either way, exactly what its product list shows" do
    create(:block, blocker: owner, blocked: blocked)
    expect(count_for(blocked)).to eq(0)
    expect(feed_count_for(blocked)).to eq(0)

    Block.delete_all
    create(:block, blocker: blocked, blocked: owner)
    expect(count_for(blocked)).to eq(0)
  end

  it "the viewer's own 'Not interested' hides drop out too, like the list" do
    buyer.hidden_listings.create!(listing: products.first)
    expect(count_for(buyer)).to eq(2)
    expect(feed_count_for(buyer)).to eq(2)
  end

  it "My shops counts as the member sees them" do
    get "/api/v1/my/shops", headers: auth_headers_for(owner)
    expect(JSON.parse(response.body)["shops"].first["listings_count"]).to eq(3)
  end
end
