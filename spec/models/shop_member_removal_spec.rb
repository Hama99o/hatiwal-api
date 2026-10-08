require "rails_helper"

# Review 2026-10-08 (HIGH): a member who leaves or is removed kept control of
# the shop products they had posted (manageable_by? passed on user_id alone)
# and the products stayed theirs. Now their products go to the owner, the
# way closing the shop already does, and a shop product is managed by the
# shop's CURRENT members only.
RSpec.describe "Leaving a shop hands the member's products to the owner" do
  let(:owner) { create(:user) }
  let(:staff) { create(:user) }
  let(:shop)  { create(:shop, owner: owner) }
  let!(:membership) { shop.shop_members.create!(user: staff, role: :staff) }
  let!(:product)    { create(:listing, :active, user: staff, shop: shop) }
  let!(:personal)   { create(:listing, :active, user: staff) }

  shared_examples "the shop keeps the product" do
    it "the product becomes the owner's, stays in the shop; the personal listing stays the member's" do
      expect(product.reload.user_id).to eq(owner.id)
      expect(product.shop_id).to eq(shop.id)
      expect(personal.reload.user_id).to eq(staff.id)
    end

    it "the former member can no longer manage it" do
      expect(product.reload.manageable_by?(staff)).to be(false)
      expect(staff.manageable_listings).not_to include(product)
      expect(staff.manageable_listings).to include(personal)
    end

    it "the expiry reminder goes to the owner" do
      expect(ListingExpiryReminderJob.new.send(:recipient_for, product.reload)).to eq(owner)
    end
  end

  context "when removed by the owner" do
    before { shop.remove_team_member!(staff, by: owner) }

    it_behaves_like "the shop keeps the product"
  end

  context "when they leave" do
    before { shop.leave!(staff) }

    it_behaves_like "the shop keeps the product"
  end

  it "a shop product is managed by its current members only, even its poster" do
    shop.shop_members.where(user: staff).delete_all # membership gone, product untouched
    expect(product.reload.manageable_by?(staff)).to be(false)
    expect(product.manageable_by?(owner)).to be(true)
  end
end
