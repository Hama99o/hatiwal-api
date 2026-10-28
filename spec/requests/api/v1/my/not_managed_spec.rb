require "rails_helper"

# QA audit 2026-10-27 A5 — removed from the shop with a write queued on the
# phone. A listing or sale outside the caller's reach used to answer 404, and
# the app's queue treats 404 on a delete or a void as "gone already: done", so
# the seller was never told the write did not happen. Not theirs any more is
# 403 with a code; a row that does not exist is still 404.
RSpec.describe "Writes on a listing or sale the caller no longer manages", type: :request do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:buyer) { create(:user) }
  let(:product) { create(:listing, :active, user: owner, shop: shop) }

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user).merge("Content-Type" => "application/json")

  def remove_from_shop(user)
    shop.remove_team_member!(user, by: owner)
  end

  it "a listing of the shop, after the member was removed: 403 listing_not_managed, nothing changes" do
    staff
    product # it existed while they were in the shop (one made after they left is a 404: offline_security_spec)
    remove_from_shop(staff)
    delete "/api/v1/my/listings/#{product.id}", headers: h(staff)

    expect(response).to have_http_status(:forbidden)
    expect(json["code"]).to eq("listing_not_managed")
    expect(product.reload.removed_at).to be_nil
  end

  it "someone who never managed it learns nothing: a plain 404, as before" do
    delete "/api/v1/my/listings/#{product.id}", headers: h(create(:user))
    expect(response).to have_http_status(:not_found)
  end

  it "someone else's sale is a plain 404" do
    Conversations::StartService.new(buyer: buyer, listing: product, message_body: "I'll take it").call
    put "/api/v1/my/listings/#{product.id}/sold", params: { buyer_id: buyer.id }.to_json, headers: h(owner)
    delete "/api/v1/my/transactions/#{product.reload.sale_transactions.sole.id}", headers: h(create(:user))
    expect(response).to have_http_status(:not_found)
  end

  it "a listing that does not exist is still 404" do
    delete "/api/v1/my/listings/#{Listing.maximum(:id).to_i + 1000}", headers: h(staff)
    expect(response).to have_http_status(:not_found)
  end

  it "a sale the member recorded for the shop, after they were removed: 403 sale_not_managed, the sale stands" do
    Conversations::StartService.new(buyer: buyer, listing: product, message_body: "I'll take it").call
    put "/api/v1/my/listings/#{product.id}/sold", params: { buyer_id: buyer.id }.to_json, headers: h(staff)
    sale = product.reload.sale_transactions.sole
    remove_from_shop(staff)

    delete "/api/v1/my/transactions/#{sale.id}", headers: h(staff)

    expect(response).to have_http_status(:forbidden)
    expect(json["code"]).to eq("sale_not_managed")
    expect(sale.reload.status).to eq("sold")
  end

  it "a sale that does not exist is still 404" do
    delete "/api/v1/my/transactions/#{Transaction.maximum(:id).to_i + 1000}", headers: h(staff)
    expect(response).to have_http_status(:not_found)
  end

  # Coverage pass 2026-10-28: a product the member posted THEMSELVES for the shop.
  # Removal hands it to the owner (Shop#drop_member!), so it is a former shop
  # listing like any other: told, not a silent 404.
  it "the member's own product of the shop, after they were removed: handed to the owner, 403 listing_not_managed" do
    own = create(:listing, :active, user: staff, shop: shop)
    remove_from_shop(staff)
    expect(own.reload.user_id).to eq(owner.id)
    delete "/api/v1/my/listings/#{own.id}", headers: h(staff)

    expect(response).to have_http_status(:forbidden)
    expect(json["code"]).to eq("listing_not_managed")
    expect(own.reload.removed_at).to be_nil
  end
end
