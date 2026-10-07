require "swagger_helper"

# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5).
# Rules and the photo copy: spec/services/listings/duplicate_service_spec.rb.
RSpec.describe "Api::V1::My::Listings duplicate", type: :request do
  let(:owner)   { create(:user) }
  let(:headers) { auth_headers_for(owner) }
  let(:shop)    { create(:shop, owner: owner, name: "Safi Mobile") }

  path "/api/v1/my/listings/{id}/duplicate" do
    parameter name: :id, in: :path, type: :integer, required: true

    post("duplicate one of the caller's listings as a draft, photos copied") do
      tags "Listings"
      description <<~DESC
        A new DRAFT with the listing's text, price, category, place and COPIES of
        its photos (new files: deleting either listing never affects the other's).
        `shop_id`: where it goes — a shop the caller is on, or null for Me (out of
        a shop only for the poster or the shop's owner). Clients open the draft in
        the edit form. Error codes: move_not_member (403), duplicate_forbidden
        (403), shop_unavailable (422).
      DESC
      consumes "application/json"
      produces "application/json"

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { shop_id: { type: :integer, nullable: true } }
      }

      let(:record) { create(:listing, :active, :with_image, user: owner) }
      let(:id)     { record.id }
      let(:body)   { { shop_id: shop.id } }

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "403", "not on the target shop's team" do
        let(:body) { { shop_id: create(:shop).id } }
        run_test! { expect(JSON.parse(response.body)["code"]).to eq("move_not_member") }
      end

      response "201", "the draft, with its photos" do
        run_test! do |response|
          listing = JSON.parse(response.body)["listing"]
          expect(listing["status"]).to eq("draft")
          expect(listing["shop"]["id"]).to eq(shop.id)
          expect(listing["images"].size).to eq(1)
          expect(listing["id"]).not_to eq(record.id)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  it "the seller deleting the original (DELETE) leaves the duplicate's photos" do
    original = create(:listing, :active, :with_image, user: owner)
    post "/api/v1/my/listings/#{original.id}/duplicate", params: { shop_id: nil }, headers: headers, as: :json
    copy = Listing.find(JSON.parse(response.body)["listing"]["id"])

    delete "/api/v1/my/listings/#{original.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(copy.reload.images.count).to eq(1)
    expect(copy.images.first.blob.service.exist?(copy.images.first.blob.key)).to be(true)
  end

  it "cannot reach a listing the caller doesn't manage" do
    post "/api/v1/my/listings/#{create(:listing, :active).id}/duplicate", params: {}, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
