require "rails_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): buyers never see
# an expiry date — only the seller (and their shop team) does.
RSpec.describe "Listing expiry date is the seller's only", type: :request do
  let(:seller)  { create(:user) }
  let(:listing) { create(:listing, :active, user: seller, expires_at: 40.days.from_now) }

  def listing_json(headers = {})
    get "/api/v1/listings/#{listing.id}", headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)["listing"]
  end

  it "hides it from a guest" do
    body = listing_json
    expect(body["expires_at"]).to be_nil
    expect(body["expired"]).to be(false)
  end

  it "hides it from a signed-in buyer" do
    expect(listing_json(auth_headers_for(create(:user)))["expires_at"]).to be_nil
  end

  it "shows it to the seller on the public page" do
    expect(Time.zone.parse(listing_json(auth_headers_for(seller))["expires_at"]))
      .to be_within(1.second).of(listing.expires_at)
  end

  it "shows it to a member of the listing's shop" do
    shop = create(:shop, owner: seller)
    listing.update!(shop: shop)
    member = create(:user)
    shop.shop_members.create!(user: member, role: :manager)

    expect(listing_json(auth_headers_for(member))["expires_at"]).to be_present
  end

  it "is still on the seller's own screens" do
    headers = auth_headers_for(seller)
    get "/api/v1/my/listings/#{listing.id}", headers: headers
    expect(JSON.parse(response.body)["listing"]["expires_at"]).to be_present

    get "/api/v1/my/listings", headers: headers
    expect(JSON.parse(response.body)["listings"].first["expires_at"]).to be_present
  end
end
