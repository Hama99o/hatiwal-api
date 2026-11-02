require "rails_helper"

# A shop OWNER suspended (their own 3 account strikes, or an admin) takes the
# shop dark for buyers — computed, auto-restored when the owner is reinstated
# (owner, 2026-10-16). A plain team member's suspension does not. The taken-down
# listing itself stays a draft; the rest reappear active.
RSpec.describe "A shop while its owner is suspended", type: :request do
  let(:owner)  { create(:user, :confirmed) }
  let(:shop)   { create(:shop, owner: owner) }
  let(:member) { create(:user, :confirmed).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let!(:listing) { create(:listing, :active, user: member, shop: shop, title: "Shop Phone") }
  let(:buyer)  { create(:user, :confirmed) }

  def feed_ids
    get "/api/v1/listings", headers: auth_headers_for(buyer)
    response.parsed_body["listings"].map { |l| l["id"] }
  end

  it "keeps the shop and its listings visible while everyone is active" do
    expect(feed_ids).to include(listing.id)
    get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(buyer)
    expect(response).to have_http_status(:ok)
  end

  context "when the owner is suspended" do
    before { owner.suspended! }

    it "drops the shop's listings out of the buyer feed (even posted by an active member)" do
      expect(feed_ids).not_to include(listing.id)
    end

    it "hides the public shop page from a buyer but keeps it for a (non-suspended) team member" do
      get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(buyer)
      expect(response).not_to have_http_status(:ok)
      # The owner is suspended (blocked from the API), but the rest of the team keeps access.
      get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(member)
      expect(response).to have_http_status(:ok)
    end

    it "comes back automatically when the owner is reinstated — no second step, listing still active" do
      owner.active!
      expect(feed_ids).to include(listing.id)
      expect(listing.reload).to be_active
    end
  end

  it "a suspended PLAIN MEMBER does not take the shop down (only their own access)" do
    member.suspended!
    # The listing was posted by the now-suspended member, so from_active_sellers
    # hides that row — but the SHOP stays up and the owner's own listings show.
    owner_listing = create(:listing, :active, user: owner, shop: shop, title: "Owner Phone")
    expect(feed_ids).to include(owner_listing.id)
    get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(buyer)
    expect(response).to have_http_status(:ok)
  end
end
