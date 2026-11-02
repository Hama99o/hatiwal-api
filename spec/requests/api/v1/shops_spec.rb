require "swagger_helper"

# SHOP-1 — hatiwal-mobile/docs/SHOPS.md
RSpec.describe "Api::V1::Shops", type: :request do
  let(:owner)    { create(:user, :confirmed) }
  let(:headers)  { auth_headers_for(owner) }
  let(:category) { create(:category) }
  let(:shop_body) do
    { shop: { name: "Safi Cosmetics", category_id: category.id, latitude: 34.3529, longitude: 62.204,
              address_line: "Near Kabul Bank, 3rd floor", hours: { sat: [ %w[08:00 18:00] ], fri: [] } } }
  end

  path "/api/v1/shops" do
    post "open your shop" do
      tags "Shops"
      description "Only name, category and location (pin + address line) are required. One shop per user " \
                  "(phase 1). The location must be in Afghanistan, Pakistan or Iran. Live at once unless " \
                  "SHOP_APPROVAL_REQUIRED is on, when it starts `pending`. Multipart for logo/cover; `hours` may be JSON."
      consumes "application/json", "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          shop: {
            type: :object,
            properties: {
              name: { type: :string, minLength: 2, maxLength: 50 }, description: { type: :string, maxLength: 160 },
              category_id: { type: :integer }, latitude: { type: :number }, longitude: { type: :number },
              province: { type: :string }, city: { type: :string }, address_line: { type: :string },
              phone: { type: :string }, phone_public: { type: :boolean },
              hours: { type: :object, example: { sat: [ %w[08:00 18:00] ], fri: [] } }
            },
            required: %w[name category_id latitude longitude address_line]
          }
        },
        required: [ "shop" ]
      }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "201", "shop opened" do
        let(:body) { shop_body }

        run_test! do
          json = JSON.parse(response.body)["shop"]
          expect(json).to include("name" => "Safi Cosmetics", "status" => "active", "role" => "owner", "province" => "Herat")
          expect(owner.reload.owned_shops.count).to eq(1)
        end
      end

      response "422", "outside the service area, or a second shop" do
        let(:body) { shop_body.deep_merge(shop: { latitude: 25.2, longitude: 55.27 }) }

        run_test!
      end

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        let(:body)           { shop_body }

        run_test!
      end
    end
  end

  path "/api/v1/shops/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "a shop page (public)" do
      tags "Shops"
      produces "application/json"

      response "200", "the shop; phone only when phone_public" do
        let(:shop) { create(:shop, phone_public: false) }
        let(:id) { shop.id }

        run_test! do
          json = JSON.parse(response.body)["shop"]
          expect(json).to include("name" => shop.name, "phone" => nil, "verified" => false, "listings_count" => 0)
          # SHOP-2: status is public (a non-member only ever sees an active shop); role stays members-only.
          expect(json).to include("status" => "active")
          expect(json.keys).not_to include("role", "phone_public")
        end
      end

      response "403", "a suspended shop is not public" do
        let(:id) { create(:shop, :suspended).id }

        run_test!
      end
    end
  end

  def json_headers = headers.merge("Content-Type" => "application/json")

  it "refuses the same shop twice, with a code the form can translate and the shop it duplicates" do
    first = create(:shop, owner: owner, name: shop_body[:shop][:name], latitude: shop_body[:shop][:latitude],
                          longitude: shop_body[:shop][:longitude])
    post "/api/v1/shops", params: shop_body.to_json, headers: json_headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include("code" => "shop_duplicate", "duplicate_shop_id" => first.id)
  end

  it "names a location abroad with its own code" do
    post "/api/v1/shops", params: shop_body.deep_merge(shop: { latitude: 25.2, longitude: 55.27 }).to_json, headers: json_headers
    expect(JSON.parse(response.body)["code"]).to eq("outside_service_area")
  end

  it "accepts hours as a JSON string (multipart forms)" do
    post "/api/v1/shops", params: shop_body.deep_merge(shop: { hours: '{"sat":[["09:00","17:00"]]}' }).to_json, headers: json_headers
    expect(response).to have_http_status(:created)
    expect(Shop.last.hours).to eq("sat" => [ %w[09:00 17:00] ])
  end

  it "lets the owner edit, and nobody else" do
    shop = create(:shop, owner: owner)
    patch "/api/v1/shops/#{shop.id}", params: { shop: { name: "Safi Beauty" } }.to_json, headers: json_headers
    expect(response).to have_http_status(:ok)
    expect(shop.reload.name).to eq("Safi Beauty")

    patch "/api/v1/shops/#{shop.id}", params: { shop: { name: "Hijacked" } }.to_json,
                                      headers: auth_headers_for(create(:user)).merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:forbidden)
  end

  it "lets the owner close it: soft, the page 404s, its products become personal" do
    shop = create(:shop, owner: owner)
    listing = create(:listing, :active, user: owner, shop: shop)
    delete "/api/v1/shops/#{shop.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(shop.reload).to be_closed
    expect(listing.reload.shop_id).to be_nil
    get "/api/v1/shops/#{shop.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/shops/#{shop.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "moves the owner's listings into the shop" do
    shop = create(:shop, owner: owner)
    mine = create(:listing, :active, user: owner)
    post "/api/v1/shops/#{shop.id}/move_listings", params: { listing_ids: [ mine.id ] }.to_json, headers: json_headers
    expect(JSON.parse(response.body)).to eq("moved" => 1)
    expect(mine.reload.shop_id).to eq(shop.id)
  end

  it "carries the share link https://<base>/s/<id> (Share my shop)" do
    shop = create(:shop)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("https://hatiwal.com")
    get "/api/v1/shops/#{shop.id}"
    expect(JSON.parse(response.body)["shop"]["share_url"]).to eq("https://hatiwal.com/s/#{shop.id}")
  end

  it "shows a suspended shop to its owner, with the owner view" do
    shop = create(:shop, :suspended, owner: owner)
    get "/api/v1/shops/#{shop.id}", headers: headers
    expect(JSON.parse(response.body)["shop"]).to include("status" => "suspended", "role" => "owner")
  end
end

RSpec.describe "SHOP-1 — selling as, my shops, feed, chats", type: :request do
  let(:owner)    { create(:user, :confirmed) }
  let(:headers)  { auth_headers_for(owner) }
  let(:json_headers) { headers.merge("Content-Type" => "application/json") }
  let!(:shop)    { create(:shop, owner: owner) }

  path "/api/v1/users/me/selling_as" do
    patch "choose who you sell as (null = Me)" do
      tags "Shops"
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: { type: :object, properties: { shop_id: { type: :integer, nullable: true } } }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "200", "saved; me.selling_as_shop shows it" do
        let(:body) { { shop_id: shop.id } }

        run_test! do
          expect(JSON.parse(response.body)["user"]["selling_as_shop"]).to include("id" => shop.id)
        end
      end

      response "422", "not a shop you are in" do
        let(:body) { { shop_id: create(:shop).id } }

        run_test! do
          expect(JSON.parse(response.body)["code"]).to eq("cannot_sell_as_shop")
        end
      end
    end
  end

  path "/api/v1/my/shops" do
    get "the shops you sell for" do
      tags "Shops"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "200", "paginated, with role and live product count" do
        before { create_list(:listing, 2, :active, user: owner, shop: shop) }

        run_test! do
          body = JSON.parse(response.body)
          expect(body["shops"].first).to include("id" => shop.id, "role" => "owner", "listings_count" => 2)
          expect(body["meta"]["pagination"]["total_count"]).to eq(1)
        end
      end
    end
  end

  it "posts a new listing as the shop while selling as it, and as Me otherwise" do
    category = create(:category)
    params = { listing: { title: "Lipstick", price: 300, currency: "AFN", category_id: category.id, location: "Herat" } }
    post "/api/v1/my/listings", params: params.to_json, headers: json_headers
    expect(Listing.last.shop_id).to be_nil

    owner.sell_as!(shop)
    post "/api/v1/my/listings", params: params.to_json, headers: json_headers
    expect(Listing.last.shop_id).to eq(shop.id)
    expect(JSON.parse(response.body)["listing"]["shop"]).to include("id" => shop.id, "name" => shop.name)
  end

  it "My listings show the identity being sold as" do
    personal = create(:listing, user: owner)
    in_shop = create(:listing, user: owner, shop: shop)
    get "/api/v1/my/listings", headers: headers
    expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).to eq([ personal.id ])
    owner.sell_as!(shop)
    get "/api/v1/my/listings", headers: headers
    expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).to eq([ in_shop.id ])
  end

  describe "the Bazaar" do
    let!(:personal) { create(:listing, :active) }
    let!(:from_shop) { create(:listing, :active, user: owner, shop: shop) }

    def feed_ids(params = {})
      get "/api/v1/listings", params: params
      JSON.parse(response.body)["listings"].map { |l| l["id"] }
    end

    it "seller_type=shop returns only shop listings, with the shop block" do
      expect(feed_ids(seller_type: "shop")).to eq([ from_shop.id ])
      expect(JSON.parse(response.body)["listings"].first["shop"]).to include("id" => shop.id, "verified" => false)
    end

    it "shop_id= is a shop page's products" do
      expect(feed_ids(shop_id: shop.id)).to eq([ from_shop.id ])
    end

    it "hides a suspended shop's products" do
      shop.suspended!
      expect(feed_ids).to eq([ personal.id ])
    end

    it "renders the shop block without a query per listing" do
      count_queries = lambda do
        n = 0
        ActiveSupport::Notifications.subscribed(->(*, p) { n += 1 if p[:sql].start_with?("SELECT") }, "sql.active_record") { get "/api/v1/listings", params: { seller_type: "shop" } }
        n
      end
      count_queries.call # warm-up. SELECTs only: devise rotates the token with an UPDATE on its own clock
      baseline = count_queries.call
      other_shops = create_list(:shop, 4)
      other_shops.each { |s| create(:listing, :active, user: s.owner, shop: s) }
      expect(count_queries.call).to eq(baseline)
    end
  end

  describe "chats" do
    let!(:shop_chat) { create(:conversation, listing: create(:listing, :active, user: owner, shop: shop)) }
    let!(:personal_chat) { create(:conversation, listing: create(:listing, :active, user: owner)) }

    def chat_ids(params = {})
      get "/api/v1/conversations", params: params, headers: headers
      JSON.parse(response.body)["conversations"].map { |c| c["id"] }
    end

    it "filters by the identity: a shop's chats, or the personal ones" do
      expect(chat_ids(shop_id: shop.id)).to eq([ shop_chat.id ])
      expect(chat_ids(shop_id: "none")).to eq([ personal_chat.id ])
      expect(chat_ids).to contain_exactly(shop_chat.id, personal_chat.id)
    end

    it "carries the shop block for the buyer" do
      get "/api/v1/conversations", headers: auth_headers_for(shop_chat.buyer)
      row = JSON.parse(response.body)["conversations"].first
      expect(row["shop"]).to include("id" => shop.id, "name" => shop.name)
    end

    it "renders the shop block on inbox rows without a query per row" do
      count_queries = lambda do
        n = 0
        ActiveSupport::Notifications.subscribed(->(*, p) { n += 1 if p[:sql].start_with?("SELECT") }, "sql.active_record") { get "/api/v1/conversations", headers: headers }
        n
      end
      # The BUYER's inbox: each row a different shop, so a per-row shop lookup
      # would show as one query per row.
      buyer = create(:user)
      buyer_headers = auth_headers_for(buyer)
      chat_with_new_shop = lambda do
        s = create(:shop)
        create(:conversation, buyer: buyer, listing: create(:listing, :active, user: s.owner, shop: s))
      end
      count_queries = lambda do
        n = 0
        ActiveSupport::Notifications.subscribed(->(*, p) { n += 1 if p[:sql].start_with?("SELECT") }, "sql.active_record") { get "/api/v1/conversations", headers: buyer_headers }
        n
      end
      3.times { chat_with_new_shop.call }
      count_queries.call # warm-up. SELECTs only: devise rotates the token with an UPDATE on its own clock
      with_three = count_queries.call
      6.times { chat_with_new_shop.call }
      expect(count_queries.call).to eq(with_three)
    end

    it "refuses another shop's chats" do
      get "/api/v1/conversations", params: { shop_id: create(:shop).id }, headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end

# Don't break the flow: a user with no shop sells exactly as before.
RSpec.describe "SHOP-1 regression — selling without a shop", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

  it "keeps create, My listings, counts and me unchanged" do
    category = create(:category)
    old = create(:listing, :active, user: user)
    post "/api/v1/my/listings", params: { listing: { title: "Bike", price: 900, currency: "AFN", category_id: category.id, location: "Kabul" } }.to_json,
                                headers: headers
    expect(response).to have_http_status(:created)
    created = JSON.parse(response.body)["listing"]
    expect(created["shop"]).to be_nil

    get "/api/v1/my/listings", headers: headers
    expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).to contain_exactly(old.id, created["id"])

    get "/api/v1/my/listings/status_counts", headers: headers
    expect(JSON.parse(response.body)).to include("all" => 2, "active" => 1, "draft" => 1)

    get "/api/v1/users/me", headers: headers
    expect(JSON.parse(response.body)["user"]).to include("selling_as_shop" => nil, "shops" => [])

    get "/api/v1/listings"
    expect(JSON.parse(response.body)["listings"].map { |l| l["shop"] }).to all(be_nil)
  end
end
