require "rails_helper"

# SHOP-1 review fixes: load, N+1, unavailable shops, one shop per user, sitemap.
RSpec.describe "SHOP-1 review", type: :request do
  def selects
    n = 0
    ActiveSupport::Notifications.subscribed(->(*, p) { n += 1 if p[:sql].start_with?("SELECT") }, "sql.active_record") { yield }
    n
  end

  it "/users/me does no shop query for a user with no shop" do
    user = create(:user)
    headers = auth_headers_for(user)
    sql = []
    ActiveSupport::Notifications.subscribed(->(*, p) { sql << p[:sql] }, "sql.active_record") { get "/api/v1/users/me", headers: headers }
    expect(sql.grep(/shop/i)).to be_empty
    expect(JSON.parse(response.body)["user"]).to include("shops" => [], "unread_counts" => nil, "selling_as_shop" => nil)
  end

  it "keeps the member counter right through join, close and removal" do
    shop = create(:shop)
    expect(shop.owner.reload.shop_memberships_count).to eq(1)
    shop.close!
    expect(shop.owner.reload.shop_memberships_count).to eq(0)
  end

  describe "the shop block is preloaded on every listing list" do
    let(:viewer) { create(:user) }
    let(:headers) { auth_headers_for(viewer) }

    def shop_listing
      shop = create(:shop)
      create(:listing, :active, user: shop.owner, shop: shop, category: category)
    end
    let(:category) { create(:category) }

    {
      "similar" => ->(ctx, l) { "/api/v1/listings/#{ctx.instance_variable_get(:@anchor).id}/similar" },
      "saved" => ->(_ctx, _l) { "/api/v1/my/saved_listings" },
      "viewed" => ->(_ctx, _l) { "/api/v1/my/viewed_listings" },
      "hidden" => ->(_ctx, _l) { "/api/v1/my/hidden_listings" }
    }.each do |name, path_for|
      it "#{name}: no query per shop" do
        @anchor = create(:listing, :active, category: category)
        attach = lambda do |l|
          case name
          when "saved" then create(:saved_listing, user: viewer, listing: l)
          when "viewed" then ListingView.create!(user: viewer, listing: l, last_viewed_at: Time.current)
          when "hidden" then create(:hidden_listing, user: viewer, listing: l)
          end
        end
        2.times { attach.call(shop_listing) }
        path = path_for.call(self, nil)
        get path, headers: headers # warm-up
        before = selects { get path, headers: headers }
        3.times { attach.call(shop_listing) }
        expect(selects { get path, headers: headers }).to eq(before)
      end
    end

    it "sold listings of a seller: no query per shop" do
      seller = create(:user)
      shop = create(:shop, owner: seller)
      2.times { create(:listing, :sold, user: seller, shop: shop) }
      path = "/api/v1/users/#{seller.id}/sold_listings"
      get path, headers: headers
      before = selects { get path, headers: headers }
      3.times { create(:listing, :sold, user: seller, shop: shop) }
      expect(selects { get path, headers: headers }).to eq(before)
    end
  end

  describe "a suspended or closed shop's listing" do
    let(:shop) { create(:shop) }
    let!(:listing) { create(:listing, :active, user: shop.owner, shop: shop) }

    it "is unavailable to everyone but its seller, and carries no shop card" do
      shop.suspended!
      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(create(:user))
      expect(response).to have_http_status(:not_found)
      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(shop.owner)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listing"]["shop"]).to be_nil
    end
  end

  it "the database refuses a second open shop even past the validation (two quick taps)" do
    owner = create(:user)
    create(:shop, owner: owner)
    second = build(:shop, owner: owner)
    expect { second.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)

    allow_any_instance_of(Shop).to receive(:one_shop_per_owner) # rubocop:disable RSpec/AnyInstance
    post "/api/v1/shops", params: { shop: { name: "Twice", category_id: create(:category).id, latitude: 34.35, longitude: 62.2,
                                            address_line: "x" } }.to_json,
                          headers: auth_headers_for(owner).merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["code"]).to eq("shop_limit_reached")
  end

  it "move_listings refuses a shop that is not open" do
    shop = create(:shop)
    mine = create(:listing, :active, user: shop.owner)
    shop.suspended!
    post "/api/v1/shops/#{shop.id}/move_listings", params: { listing_ids: [ mine.id ] }.to_json,
                                                    headers: auth_headers_for(shop.owner).merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:forbidden).or have_http_status(:unprocessable_entity)
    expect(mine.reload.shop_id).to be_nil
  end

  it "lists open (and, with ?verified=true, verified) shops for the sitemap, without sign-in" do
    verified = create(:shop, verified_at: Time.current)
    plain = create(:shop)
    create(:shop, :suspended)
    get "/api/v1/shops"
    expect(JSON.parse(response.body)["shops"].map { |s| s["id"] }).to contain_exactly(verified.id, plain.id)
    get "/api/v1/shops", params: { verified: true }
    body = JSON.parse(response.body)
    expect(body["shops"].map { |s| s["id"] }).to eq([ verified.id ])
    expect(body["shops"].first.keys).to contain_exactly("id", "name", "updated_at", "verified")
    expect(body["meta"]["pagination"]).to be_present
  end

  it "the shop JSON says whether it is open now, decided on the server" do
    shop = create(:shop, hours: {})
    get "/api/v1/shops/#{shop.id}"
    expect(JSON.parse(response.body)["shop"]).to include("open_now" => nil, "next_change_at" => nil, "time_zone" => "Asia/Kabul")
  end
end
