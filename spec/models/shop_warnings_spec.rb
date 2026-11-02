require "rails_helper"

# Shop strikes (owner, 2026-10-16): the business answers for what it sells.
RSpec.describe Shop, "prohibited-item strikes" do
  let(:owner) { create(:user) }
  let(:shop)  { create(:shop, owner: owner) }

  describe "#issue_warning!" do
    it "records a shop warning and counts the active ones" do
      shop.issue_warning!(reason: "Prohibited item: firearms", category: :prohibited_item)
      expect(shop.active_warnings_count).to eq(1)
      expect(shop.warnings.last).to have_attributes(shop_id: shop.id, user_id: nil, category: "prohibited_item")
    end

    it "suspends the shop at the threshold, through the existing path" do
      (Shop::SHOP_WARNING_BLOCK_THRESHOLD - 1).times { shop.issue_warning!(reason: "x", category: :prohibited_item) }
      expect(shop.reload).to be_active
      shop.issue_warning!(reason: "last", category: :prohibited_item)
      expect(shop.reload).to be_suspended
    end

    it "does not count expired warnings toward suspension" do
      create_list(:user_warning, Shop::SHOP_WARNING_BLOCK_THRESHOLD, :for_shop, :expired, shop: shop)
      shop.issue_warning!(reason: "fresh", category: :prohibited_item)
      expect([ shop.active_warnings_count, shop.reload.suspended? ]).to eq([ 1, false ])
    end

    it "records the poster and the listing on a shop warning" do
      poster = create(:user)
      shop.shop_members.create!(user: poster, role: :staff)
      listing = create(:listing, :active, user: poster, shop: shop, title: "AK")
      warning = shop.issue_warning!(reason: "r", category: :prohibited_item, posted_by: poster, listing: listing)
      expect(warning).to have_attributes(posted_by_id: poster.id, listing_id: listing.id)
    end
  end

  describe "availability while the owner is suspended (computed, owner 2026-10-16)" do
    it "#available_to_buyers? is false and the shop drops out of .visible" do
      shop # create while owner active
      expect(Shop.visible).to include(shop)
      owner.suspended!
      expect(shop.reload.available_to_buyers?).to be(false)
      expect(Shop.visible).not_to include(shop)
    end

    it "comes back automatically when the owner is reinstated (no second step)" do
      owner.suspended!
      expect(Shop.visible).not_to include(shop)
      owner.active!
      expect(shop.reload.available_to_buyers?).to be(true)
      expect(Shop.visible).to include(shop)
    end
  end
end
