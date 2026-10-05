require "rails_helper"

# SHOP-3 DoD (API): products and sales — a staff member edits and marks Sold a
# product the owner posted; the Transaction's seller is the owner with
# recorded_by = staff; the review goes to the owner.
RSpec.describe "Shop team products and sales", type: :request do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:buyer) { create(:user) }
  let(:product) { create(:listing, :active, user: owner, shop: shop) }

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user).merge("Content-Type" => "application/json")

  it "staff edits a product the owner posted" do
    put "/api/v1/my/listings/#{product.id}", params: { listing: { title: "New title by staff" } }.to_json, headers: h(staff)
    expect(response).to have_http_status(:ok)
    expect(product.reload.title).to eq("New title by staff")
  end

  it "My shop lists every product of the shop for every member" do
    mine = create(:listing, :active, user: staff, shop: shop)
    product
    staff.update!(active_shop: shop)
    get "/api/v1/my/listings", headers: auth_headers_for(staff)
    expect(json["listings"].pluck("id")).to include(product.id, mine.id)
  end

  it "staff marks Sold: the seller is the owner, recorded_by the staff member, the review goes to the owner" do
    Conversations::StartService.new(buyer: buyer, listing: product, message_body: "I'll take it").call
    put "/api/v1/my/listings/#{product.id}/sold", params: { buyer_id: buyer.id }.to_json, headers: h(staff)
    expect(response).to have_http_status(:ok)
    sale = product.reload.sale_transactions.sole
    expect(sale).to have_attributes(seller_id: owner.id, recorded_by_id: staff.id, buyer_id: buyer.id, status: "sold")

    # The staff member sees the sale they recorded; the owner, as seller, too.
    get "/api/v1/my/transactions", headers: auth_headers_for(staff)
    expect(json["transactions"].pluck("id")).to include(sale.id)
  end

  it "a non-member can't touch a shop product" do
    put "/api/v1/my/listings/#{product.id}", params: { listing: { title: "Nope" } }.to_json, headers: h(create(:user))
    expect(response).to have_http_status(:not_found)
  end

  it "a removed member can't touch it any more" do
    shop.remove_team_member!(staff, by: owner)
    put "/api/v1/my/listings/#{product.id}", params: { listing: { title: "Nope" } }.to_json, headers: h(staff)
    expect(response).to have_http_status(:not_found)
  end

  it "closing the shop gives a STAFF-posted product to the OWNER, not to the staff member" do
    staff_product = create(:listing, :active, user: staff, shop: shop)
    product
    shop.close!
    expect(staff_product.reload).to have_attributes(user_id: owner.id, shop_id: nil)
    expect(product.reload).to have_attributes(user_id: owner.id, shop_id: nil)
    expect(staff.listings).to be_empty
  end
end
