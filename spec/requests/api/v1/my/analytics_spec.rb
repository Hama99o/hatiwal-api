require "swagger_helper"

# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 2;
# docs/design/SELLER_ANALYTICS.md): numbers for ONE identity, never global.
RSpec.describe "Api::V1::My::Analytics", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }
  let(:shop)    { create(:shop, owner: seller, name: "Safi Mobile") }

  # Me: 2 active (one held), 1 expired, 1 sold, 1 draft, 1 removed (not counted).
  # The shop: 1 active. Someone else: 1 active (never counted).
  before do
    create(:listing, :active, user: seller, views_count: 10)
    create(:listing, :reserved, user: seller, views_count: 5)
    create(:listing, :active, user: seller, expires_at: 2.days.ago, views_count: 1)
    create(:listing, :sold, user: seller)
    create(:listing, :draft, user: seller)
    create(:listing, :active, user: seller, removed_at: Time.current, views_count: 100)
    create(:listing, :active, user: seller, shop: shop, views_count: 7)
    create(:listing, :active, views_count: 1000)
  end

  path "/api/v1/my/analytics" do
    get("a seller's numbers, for Me or one shop they are on") do
      tags "Listings"
      description <<~DESC
        `shop_id`: a shop the caller is on (any role), or none for Me. Counts:
        total (not removed), active (live, not expired), expired, sold, draft,
        sales + units_sold (recorded sales), views (sum), chats (begun with this
        identity). Never site-wide. 403 `not_a_member` for another shop.
      DESC
      produces "application/json"

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false
      parameter name: :shop_id, in: :query, type: :integer, required: false

      let(:shop_id) { nil }

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "403", "not on that shop's team" do
        let(:shop_id) { create(:shop).id }
        run_test! { expect(JSON.parse(response.body)["code"]).to eq("not_a_member") }
      end

      response "200", "Me" do
        run_test! do |response|
          a = JSON.parse(response.body)["analytics"]
          expect(a.slice("total", "active", "expired", "sold", "draft", "views"))
            .to eq("total" => 5, "active" => 2, "expired" => 1, "sold" => 1, "draft" => 1, "views" => 16)
          expect(a["shop"]).to be_nil
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  it "a shop's numbers are the shop's only, and every member sees them" do
    staff = create(:user)
    shop.shop_members.create!(user: staff, role: :staff)

    get "/api/v1/my/analytics", params: { shop_id: shop.id }, headers: auth_headers_for(staff)

    a = JSON.parse(response.body)["analytics"]
    expect(a.slice("total", "active", "views")).to eq("total" => 1, "active" => 1, "views" => 7)
    expect(a["shop"]["name"]).to eq("Safi Mobile")
  end

  it "counts sales and chats per identity" do
    personal = create(:listing, :active, user: seller, quantity: 5)
    create(:transaction, :sold, seller: seller, listing: personal, quantity: 3)
    get "/api/v1/my/analytics", headers: headers
    a = JSON.parse(response.body)["analytics"]
    expect(a.slice("sales", "units_sold", "chats")).to eq("sales" => 1, "units_sold" => 3, "chats" => 1)

    get "/api/v1/my/analytics", params: { shop_id: shop.id }, headers: headers
    expect(JSON.parse(response.body)["analytics"].slice("sales", "chats")).to eq("sales" => 0, "chats" => 0)
  end

  describe "POST /my/listings/relaunch_expired" do
    it "renews every expired listing of THAT identity, and only those" do
      shop_expired = create(:listing, :active, user: seller, shop: shop, expires_at: 1.day.ago)

      post "/api/v1/my/listings/relaunch_expired", params: {}, headers: headers, as: :json

      expect(JSON.parse(response.body)).to eq("renewed" => 1, "failed" => 0)
      expect(seller.listings.where(shop_id: nil).expired_active).to be_empty
      expect(shop_expired.reload).to be_expired # the shop's are the shop's

      post "/api/v1/my/listings/relaunch_expired", params: { shop_id: shop.id }, headers: headers, as: :json
      expect(JSON.parse(response.body)).to eq("renewed" => 1, "failed" => 0)
      expect(shop_expired.reload.expires_at).to be > 89.days.from_now
    end

    it "counts a listing that cannot be renewed instead of failing the batch" do
      bad = create(:listing, :active, user: seller, expires_at: 1.day.ago)
      bad.update_column(:latitude, 91)

      post "/api/v1/my/listings/relaunch_expired", params: {}, headers: headers, as: :json
      expect(JSON.parse(response.body)).to eq("renewed" => 1, "failed" => 1)
    end

    it "refuses a shop the caller is not on" do
      post "/api/v1/my/listings/relaunch_expired", params: { shop_id: create(:shop).id }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
