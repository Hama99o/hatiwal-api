require "rails_helper"

# A removed listing (deleted by its seller, taken down by an admin, or its
# account being deleted) changes no more. Found by the offline work (B4): a
# deleted listing could still be marked SOLD (and edited, published, reserved…),
# and a seller's delete replaced an admin's take-down reason (B7).
RSpec.describe "My listings — a removed listing", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }
  let(:listing) { create(:listing, :active, user: seller) }

  def body = JSON.parse(response.body)

  before { listing.update!(removed_at: Time.current, removed_reason: "deleted_by_seller") }

  {
    publish: [ :put, {}, :forbidden, "listing_removed" ], unpublish: [ :put, {}, :forbidden, "listing_removed" ],
    activate: [ :put, {}, :forbidden, "listing_removed" ], sold: [ :put, {}, :forbidden, "listing_removed" ],
    reserve: [ :put, {}, :forbidden, "listing_removed" ],
    # Already refused before, with their own codes (kept: the apps map them).
    move: [ :put, -> { { shop_id: create(:shop, owner: seller).id } }, :unprocessable_content, "move_not_movable" ],
    duplicate: [ :post, {}, :unprocessable_content, "duplicate_removed" ]
  }.each do |action, (verb, params, status, code)|
    it "#{action} → #{code}, nothing changes" do
      route = "/api/v1/my/listings/#{listing.id}/#{action}"
      params = instance_exec(&params) if params.respond_to?(:call)
      expect do
        send(verb, route, params: params, headers: headers, as: :json)
      end.not_to(change { [ listing.reload.status, listing.updated_at, Transaction.count, Listing.count ] })
      expect(response).to have_http_status(status)
      expect(body["code"]).to eq(code)
    end
  end

  it "an edit → 403 listing_removed, the title unchanged" do
    patch "/api/v1/my/listings/#{listing.id}", params: { listing: { title: "Renamed" } }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(body["code"]).to eq("listing_removed")
    expect(listing.reload.title).not_to eq("Renamed")
  end

  it "delete again (another device, a lost answer) → 204, nothing changes" do
    expect do
      delete "/api/v1/my/listings/#{listing.id}", headers: headers
    end.not_to(change { listing.reload.removed_at })
    expect(response).to have_http_status(:no_content)
  end

  it "the seller deleting a TAKEN-DOWN listing keeps the admin's reason (B7)" do
    listing.take_down!(reason: "Prohibited item: weapons")
    delete "/api/v1/my/listings/#{listing.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(listing.reload.removed_reason).to eq("Prohibited item: weapons")
  end
end
