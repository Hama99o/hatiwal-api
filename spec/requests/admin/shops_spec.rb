require "rails_helper"

# SHOP-1 — admin shops (hatiwal-mobile/docs/SHOPS.md, "Admin").
RSpec.describe "Admin shops", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:owner) { create(:user, email: "safi.owner@example.com", firstname: "Umair") }
  let!(:shop) { create(:shop, owner: owner, name: "Safi Cosmetics", province: "Herat") }

  before { sign_in admin, scope: :admin_user }

  describe "the list" do
    let!(:other) { create(:shop, name: "Kabul Mobile", latitude: 34.5553, longitude: 69.2075, status: :suspended) }

    it "lists shops and filters by status, province, verified and waiting" do
      get admin_shops_path
      expect(response.body).to include("Safi Cosmetics", "Kabul Mobile")

      get admin_shops_path(status: "suspended")
      expect(response.body).to include("Kabul Mobile").and(satisfy { |b| !b.include?("Safi Cosmetics") })

      get admin_shops_path(province: "Herat")
      expect(response.body).to include("Safi Cosmetics").and(satisfy { |b| !b.include?("Kabul Mobile") })

      shop.update_columns(verified_at: Time.current)
      get admin_shops_path(verified: "yes")
      expect(response.body).to include("Safi Cosmetics").and(satisfy { |b| !b.include?("Kabul Mobile") })

      waiting = create(:shop, :verification_eligible, name: "Jalalabad Waiting")
      create(:shop_verification_request, shop: waiting)
      get admin_shops_path(requested: "yes")
      expect(response.body).to include("Jalalabad Waiting").and(satisfy { |b| !b.include?("Safi Cosmetics") })
    end

    it "searches by shop name and by the owner's name or email" do
      get admin_shops_path(search: "safi.owner@")
      expect(response.body).to include("Safi Cosmetics").and(satisfy { |b| !b.include?("Kabul Mobile") })
      get admin_shops_path(search: "Umair")
      expect(response.body).to include("Safi Cosmetics")
      get admin_shops_path(search: "Kabul Mob")
      expect(response.body).to include("Kabul Mobile").and(satisfy { |b| !b.include?("Safi Cosmetics") })
    end

    it "does not run a query per row" do
      count = lambda do
        n = 0
        ActiveSupport::Notifications.subscribed(->(*, p) { n += 1 if p[:sql].start_with?("SELECT") }, "sql.active_record") { get admin_shops_path }
        n
      end
      count.call
      before = count.call
      create_list(:shop, 5)
      expect(count.call).to eq(before)
    end
  end

  it "shows the shop page with every panel" do
    create(:listing, :active, user: owner, shop: shop, title: "Rose lipstick")
    get admin_shop_path(shop)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("shop-moderation", "shop-verification", "shop-members", "shop-products",
                                     "shop-reports", "shop-history", "Rose lipstick", owner.full_name)
  end

  it "suspends: the shop leaves search, members sell as Me, it is logged" do
    listing = create(:listing, :active, user: owner, shop: shop)
    owner.update!(active_shop: shop)
    patch suspend_admin_shop_path(shop), params: { reason: "fake shop" }
    expect(shop.reload).to be_suspended
    expect(owner.reload.active_shop_id).to be_nil
    expect(Listing.browsable).not_to include(listing)
    expect(AdminAuditLog.where(action: "suspend_shop", target: shop).pick(:details)).to eq("fake shop")

    patch reactivate_admin_shop_path(shop)
    expect(shop.reload).to be_active
    expect(AdminAuditLog.where(action: "reactivate_shop", target: shop)).to exist
  end

  it "removes a member but never the owner" do
    staff = create(:shop_member, shop: shop, role: :staff)
    staff.user.update!(active_shop: shop)
    delete remove_member_admin_shop_path(shop, member_id: staff.id)
    expect(shop.shop_members.exists?(staff.id)).to be(false)
    expect(staff.user.reload.active_shop_id).to be_nil
    expect(AdminAuditLog.where(action: "remove_shop_member", target: shop)).to exist

    owner_row = shop.shop_members.find_by(user: owner)
    delete remove_member_admin_shop_path(shop, member_id: owner_row.id)
    expect(shop.shop_members.exists?(owner_row.id)).to be(true)
  end

  it "removes the Verified shop badge with a reason, and tells the owner" do
    shop.update_columns(verified_at: Time.current)
    expect do
      post remove_badge_admin_shop_path(shop), params: { reason_code: "policy_violation" }
    end.to have_enqueued_job(SupportNoticeJob).with(owner.id, "shop_badge_removed", shop.id)
    expect(shop.reload.verified?).to be(false)
  end

  it "lists a shop's products in the admin listings with ?shop_id=" do
    mine = create(:listing, :active, user: owner, shop: shop, title: "In the shop")
    create(:listing, :active, title: "Somebody else")
    get admin_listings_path(shop_id: shop.id)
    expect(response.body).to include(mine.title).and(satisfy { |b| !b.include?("Somebody else") })
  end

  it "shows shop counts on the dashboard and the shops on the user page" do
    get admin_root_path
    expect(response.body).to include("dashboard-shops", "New this week")
    get admin_user_path(owner)
    expect(response.body).to include("user-shops", "Safi Cosmetics")
  end
end
