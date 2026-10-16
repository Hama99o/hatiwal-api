require "rails_helper"

# Shop strikes in the API (owner, 2026-10-16): the members-only shop view carries
# the shop's active warning count, the threshold and the latest warning, so the
# team's banner can say "at 3 the shop is suspended". A buyer/stranger NEVER sees
# them (the :public shop face). Additive + 1.0.4-safe.
RSpec.describe "Api::V1::Shops warnings", type: :request do
  let(:owner)   { create(:user, :confirmed) }
  let(:shop)    { create(:shop, owner: owner) }
  let(:listing) { create(:listing, :active, user: owner, shop: shop, title: "Kalashnikov") }

  def get_shop(as:)
    get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(as)
    response.parsed_body.fetch("shop")
  end

  describe "the members-only (owner) view" do
    before { shop.issue_warning!(reason: "Prohibited item: firearms", category: :prohibited_item, listing: listing) }

    it "carries the count, the threshold and the latest warning for a member" do
      body = get_shop(as: owner)
      expect(body["active_warnings_count"]).to eq(1)
      expect(body["warnings_threshold"]).to eq(Shop::SHOP_WARNING_BLOCK_THRESHOLD)
      expect(body["latest_warning"]).to include(
        "category" => "prohibited_item",
        "listing_title" => "Kalashnikov"
      )
      expect(body["latest_warning"]).to have_key("created_at")
      expect(body["latest_warning"]).to have_key("reason")
    end

    it "is null when the shop has no warnings" do
      shop.warnings.destroy_all
      body = get_shop(as: owner)
      expect([ body["active_warnings_count"], body["latest_warning"] ]).to eq([ 0, nil ])
    end
  end

  describe "a buyer / stranger (public view)" do
    before { shop.issue_warning!(reason: "Prohibited item: firearms", category: :prohibited_item, listing: listing) }

    it "NEVER sees the shop's warnings" do
      body = get_shop(as: create(:user, :confirmed))
      expect(body.keys).not_to include("active_warnings_count", "warnings_threshold", "latest_warning")
    end
  end
end
