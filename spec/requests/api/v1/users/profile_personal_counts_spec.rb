require "rails_helper"

# Owner, 2026-10-07: a person's Profile is PERSONAL ("Me") whatever "Sell as" is.
# Products posted as one of their shops count on the shop, never on the person:
# not in their own stats, not in their public profile, not in its grid.
RSpec.describe "Profile counts are personal", type: :request do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }

  before do
    create_list(:listing, 2, :active, user: owner)
    create(:listing, :sold, user: owner)
    create_list(:listing, 3, :active, user: owner, shop: shop)
    create(:listing, :sold, user: owner, shop: shop)
  end

  def json = JSON.parse(response.body)

  it "me: items_active_count and items_sold_count leave out the shop's products" do
    get "/api/v1/users/me", headers: auth_headers_for(owner)
    expect(json["user"]).to include("items_active_count" => 2, "items_sold_count" => 1)
  end

  it "public profile: listings_count equals the profile grid, both personal" do
    get "/api/v1/users/#{owner.id}/public_profile", headers: auth_headers_for(create(:user))
    expect(json["user"]["listings_count"]).to eq(2)

    get "/api/v1/listings", params: { user_id: owner.id }
    ids = json["listings"].pluck("id")
    expect(ids.size).to eq(2)
    expect(Listing.where(id: ids).pluck(:shop_id).uniq).to eq([ nil ])
  end

  it "the shop's page still lists its products (shop_id), including with user_id" do
    get "/api/v1/listings", params: { shop_id: shop.id }
    expect(json["listings"].size).to eq(3)
    get "/api/v1/listings", params: { shop_id: shop.id, user_id: owner.id }
    expect(json["listings"].size).to eq(3)
  end

  it "a list of profiles (GET /blocks) counts the same way (bulk preload)" do
    fresh = User.find(owner.id)
    User.preload_public_stats([ fresh ])
    expect(fresh.live_listings_count).to eq(2)
  end
end
