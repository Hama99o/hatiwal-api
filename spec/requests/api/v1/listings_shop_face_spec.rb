require "rails_helper"

# Review 2026-10-08 (HIGH, privacy): on a SHOP product, buyers got the
# POSTER's personal identity in `seller` — name, avatar, city, and on the
# detail the personal phone and WhatsApp. A shop product's seller is the SHOP
# (as ConversationSerializer.person_block already does): the owner's id, the
# shop's name / logo / city, the shop phone only when public, as_shop: true.
# Same keys as before, so older apps still render it.
RSpec.describe "The seller of a shop product is the shop", type: :request do
  let(:owner) { create(:user, firstname: "Umair", lastname: "Owner") }
  let(:staff) do
    create(:user, firstname: "Ali", lastname: "Staff", city: "Paghman", phone: "+93700000999",
                  whatsapp_number: "+93700000998", show_phone_publicly: true, show_address_publicly: true)
  end
  let(:shop) { create(:shop, owner: owner, name: "Safi Cosmetics", city: "Kabul", phone: "+93700000111", phone_public: true) }
  let!(:membership) { shop.shop_members.create!(user: staff, role: :staff) }
  let!(:product) { create(:listing, :active, user: staff, shop: shop) }
  let(:buyer) { auth_headers_for(create(:user)) }

  def seller_in_feed
    get "/api/v1/listings", params: { shop_id: shop.id }, headers: buyer
    JSON.parse(response.body)["listings"].find { |l| l["id"] == product.id }["seller"]
  end

  def seller_on_detail
    get "/api/v1/listings/#{product.id}", headers: buyer
    JSON.parse(response.body)["listing"]["seller"]
  end

  it "the feed shows the shop, never the poster" do
    s = seller_in_feed
    expect(s.slice("id", "name", "city", "as_shop")).to eq("id" => owner.id, "name" => "Safi Cosmetics", "city" => "Kabul", "as_shop" => true)
    expect(s.to_s).not_to include("Ali", "Paghman")
  end

  it "the detail shows the shop and the SHOP phone, never the poster's phone or WhatsApp" do
    s = seller_on_detail
    expect(s.slice("id", "name", "city", "phone", "whatsapp_number", "as_shop"))
      .to eq("id" => owner.id, "name" => "Safi Cosmetics", "city" => "Kabul", "phone" => "+93700000111",
             "whatsapp_number" => nil, "as_shop" => true)
    expect(s.to_s).not_to include("Ali Staff", "+93700000999", "+93700000998", "Paghman")
    # Old apps read these keys; they are all still there.
    expect(s.keys).to include("verified", "avatar_url", "avg_rating", "review_count", "seller_is_away")
  end

  it "a private shop phone stays private" do
    shop.update!(phone_public: false)
    expect(seller_on_detail["phone"]).to be_nil
  end

  it "a personal listing is unchanged: the person" do
    personal = create(:listing, :active, user: staff)
    get "/api/v1/listings/#{personal.id}", headers: buyer
    s = JSON.parse(response.body)["listing"]["seller"]
    expect(s.slice("id", "name", "phone")).to eq("id" => staff.id, "name" => "Ali Staff", "phone" => "+93700000999")
    expect(s["as_shop"]).to be_nil
  end
end
