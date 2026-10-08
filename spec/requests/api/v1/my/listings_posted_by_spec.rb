require "rails_helper"

# Owner, 2026-10-08: on a shop's products, the TEAM sees who posted each one
# (`posted_by {id, name}`); buyers never do. Member-scoped payloads only
# (my/listings, list and detail); the public feed, listing and shop products
# never carry the key.
RSpec.describe "posted_by on shop products", type: :request do
  let(:owner) { create(:user, firstname: "Umair", lastname: "Owner") }
  let(:staff) { create(:user, firstname: "Ali", lastname: "Staff") }
  let(:shop)  { create(:shop, owner: owner) }
  let!(:membership) { shop.shop_members.create!(user: staff, role: :staff) }
  let!(:by_staff) { create(:listing, :active, user: staff, shop: shop) }
  let!(:personal) { create(:listing, :active, user: owner) }

  before do
    owner.update_column(:active_shop_id, shop.id) # selling as the shop
  end

  it "the team's My shop list names who posted each product" do
    get "/api/v1/my/listings", headers: auth_headers_for(owner)

    row = JSON.parse(response.body)["listings"].find { |l| l["id"] == by_staff.id }
    expect(row["posted_by"]).to eq("id" => staff.id, "name" => "Ali Staff")
  end

  it "the member view of one product names its poster too" do
    get "/api/v1/my/listings/#{by_staff.id}", headers: auth_headers_for(owner)

    expect(JSON.parse(response.body)["listing"]["posted_by"]).to eq("id" => staff.id, "name" => "Ali Staff")
  end

  it "a personal listing has none" do
    owner.update_column(:active_shop_id, nil)
    get "/api/v1/my/listings", headers: auth_headers_for(owner)

    row = JSON.parse(response.body)["listings"].find { |l| l["id"] == personal.id }
    expect(row["posted_by"]).to be_nil
  end

  it "buyers never see it: not on the listing, the feed, or the shop's products" do
    buyer = auth_headers_for(create(:user))

    get "/api/v1/listings/#{by_staff.id}", headers: buyer
    expect(JSON.parse(response.body)["listing"]).not_to have_key("posted_by")

    get "/api/v1/listings", params: { shop_id: shop.id }, headers: buyer
    rows = JSON.parse(response.body)["listings"]
    expect(rows.map { |l| l["id"] }).to include(by_staff.id)
    expect(rows).to all(satisfy { |l| !l.key?("posted_by") })

    get "/api/v1/listings"
    expect(JSON.parse(response.body)["listings"]).to all(satisfy { |l| !l.key?("posted_by") })
  end
end
