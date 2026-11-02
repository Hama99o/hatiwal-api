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
        A shop also gets `team` (owner 2026-10-08): one row per member
        {user {id, name, avatar_url}, role, posted, active, expired, sold}, sold
        = sales the member recorded; and `team_unattributed` {posted, active,
        expired, sold}: products of former members and sales recorded before
        recorded_by existed. Every member sees the whole team. Me: both null.
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

  # Owner, 2026-10-08: the shop's numbers per team member. Posted = the
  # member's products (not removed), active / expired of those, sold = sales
  # the member RECORDED (transactions.recorded_by). Older sales with no
  # recorder, and products of people who left, go to team_unattributed.
  describe "the Team breakdown" do
    let(:manager) { create(:user, firstname: "Mina", lastname: "Manager") }
    let(:staff)   { create(:user, firstname: "Ali", lastname: "Staff") }
    let(:former)  { create(:user) }

    before do
      shop.shop_members.create!(user: manager, role: :manager)
      shop.shop_members.create!(user: staff, role: :staff)
      # The owner already has 1 active shop product (the outer before block).
      create(:listing, :active, user: staff, shop: shop)
      create(:listing, :active, user: staff, shop: shop, expires_at: 1.day.ago)
      staff_sold = create(:listing, :active, user: staff, shop: shop, quantity: 3)
      create(:transaction, :outside_buyer, seller: seller, listing: staff_sold, recorded_by: manager)
      create(:transaction, :outside_buyer, seller: seller, listing: staff_sold, recorded_by: nil) # before recorded_by
      # Posted by someone who has since left the team.
      left = shop.shop_members.create!(user: former, role: :staff)
      create(:listing, :active, user: former, shop: shop)
      left.destroy!
    end

    def team_for(user)
      get "/api/v1/my/analytics", params: { shop_id: shop.id }, headers: auth_headers_for(user)
      JSON.parse(response.body)["analytics"]
    end

    it "one row per member (owner, manager, staff), and the rest unattributed" do
      a = team_for(seller)
      rows = a["team"].map { |r| [ r["user"]["id"], r["role"], r.slice("posted", "active", "expired", "sold") ] }
      expect(rows).to eq([
        [ seller.id,  "owner",   { "posted" => 1, "active" => 1, "expired" => 0, "sold" => 0 } ],
        [ manager.id, "manager", { "posted" => 0, "active" => 0, "expired" => 0, "sold" => 1 } ],
        [ staff.id,   "staff",   { "posted" => 3, "active" => 2, "expired" => 1, "sold" => 0 } ]
      ])
      expect(a["team"].second["user"]["name"]).to eq("Mina Manager")
      expect(a["team_unattributed"]).to eq("posted" => 1, "active" => 1, "expired" => 0, "sold" => 1)
    end

    it "staff see the whole team, like the shop's other numbers" do
      expect(team_for(staff)["team"].map { |r| r["user"]["id"] }).to eq([ seller.id, manager.id, staff.id ])
    end

    it "Me has no team" do
      get "/api/v1/my/analytics", headers: headers
      a = JSON.parse(response.body)["analytics"]
      expect([ a["team"], a["team_unattributed"] ]).to eq([ nil, nil ])
    end
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
