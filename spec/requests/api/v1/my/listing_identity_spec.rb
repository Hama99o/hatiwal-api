require "rails_helper"

# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.6) — the identity travels with the
# write. A listing created offline as a shop, then a switch back to Me before it
# synced, must still land in the shop: the app sends `shop_id` (null = Me), and
# the server checks it exactly like "sell as". Without it (every 1.1.x app),
# nothing changes: the server's current "selling as" decides.
RSpec.describe "My listings — the identity a write names", type: :request do
  let(:seller)   { create(:user) }
  let(:headers)  { auth_headers_for(seller) }
  let(:category) { create(:category) }
  let(:shop)     { create(:shop, owner: seller) }
  let(:params)   { { listing: { title: "Bike", price: 3000, currency: "AFN", category_id: category.id } } }

  def create_listing(extra = {}, as: headers)
    post "/api/v1/my/listings", params: params.merge(extra), headers: as, as: :json
  end

  def body = JSON.parse(response.body)

  it "shop_id names the shop: the listing lands there even though the server says 'selling as Me'" do
    seller.sell_as!(nil)
    expect { create_listing({ shop_id: shop.id }) }.to change(Listing, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(Listing.last.shop).to eq(shop)
  end

  it "shop_id null names Me: it lands in Me even though the server says 'selling as the shop'" do
    seller.sell_as!(shop)
    create_listing({ shop_id: nil })
    expect(response).to have_http_status(:created)
    expect(Listing.last.shop).to be_nil
  end

  it "no shop_id (every 1.1.x app): the server's current 'selling as' decides, as before" do
    seller.sell_as!(shop)
    create_listing
    expect(response).to have_http_status(:created)
    expect(Listing.last.shop).to eq(shop)
    expect(body).not_to have_key("code")
  end

  it "every shop role may post as the shop (owner, manager, staff — docs/SHOPS.md)" do
    %i[manager staff].each do |role|
      member = create(:user)
      shop.shop_members.create!(user: member, role: role)
      create_listing({ shop_id: shop.id }, as: auth_headers_for(member))
      expect(response).to have_http_status(:created), "#{role}: #{response.body}"
      expect(Listing.last.shop).to eq(shop)
    end
  end

  context "a shop it may NOT post as → 422 shop_unavailable, nothing created" do
    def expect_refused(shop_id, as: headers)
      expect { create_listing({ shop_id: shop_id }, as: as) }.not_to change(Listing, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("shop_unavailable")
    end

    it("never a member") { expect_refused(create(:shop).id) }

    it "removed from the team (the case of a switch queued before the removal)" do
      member = create(:user)
      shop.shop_members.create!(user: member, role: :staff)
      shop.shop_members.find_by(user: member).destroy!
      expect_refused(shop.id, as: auth_headers_for(member))
    end

    it "the shop is closed" do
      shop.update_columns(status: Shop.statuses[:closed])
      expect_refused(shop.id)
    end

    it "the shop is suspended" do
      shop.update_columns(status: Shop.statuses[:suspended])
      expect_refused(shop.id)
    end

    it("another user's shop id") { expect_refused(create(:shop, owner: create(:user)).id) }
    it("a shop that does not exist") { expect_refused(0) }
  end

  it "a suspended account creates nothing (refused before any action, as for every write)" do
    seller.update_columns(status: User.statuses[:suspended])
    expect { create_listing({ shop_id: shop.id }) }.not_to change(Listing, :count)
    expect(response.status).to be >= 400
  end

  describe "GET /my/listings?selling_as=" do
    let!(:mine)     { create(:listing, :active, user: seller) }
    let!(:in_shop)  { create(:listing, :active, user: seller, shop: shop) }

    def ids = body["listings"].map { |l| l["id"] }

    it "lists the identity asked for, whatever the server's 'selling as'" do
      seller.sell_as!(shop)
      get "/api/v1/my/listings", params: { selling_as: "me" }, headers: headers
      expect(ids).to eq([ mine.id ])
      seller.sell_as!(nil)
      get "/api/v1/my/listings", params: { selling_as: shop.id }, headers: headers
      expect(ids).to eq([ in_shop.id ])
    end

    it "a shop it may not see → 422 shop_unavailable" do
      get "/api/v1/my/listings", params: { selling_as: create(:shop).id }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(body["code"]).to eq("shop_unavailable")
    end

    it "no selling_as (1.1.x): as before" do
      seller.sell_as!(shop)
      get "/api/v1/my/listings", headers: headers
      expect(ids).to eq([ in_shop.id ])
    end
  end
end
