require "swagger_helper"

# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5):
# "Move to shop". Rules: Listings::MoveService (spec/services/listings).
RSpec.describe "Api::V1::My::Listings move", type: :request do
  let(:owner)   { create(:user) }
  let(:headers) { auth_headers_for(owner) }
  let(:shop)    { create(:shop, owner: owner, name: "Safi Mobile") }

  path "/api/v1/my/listings/{id}/move" do
    parameter name: :id, in: :path, type: :integer, required: true

    put("move one of the caller's listings to Me or to another shop they are on") do
      tags "Listings"
      description <<~DESC
        `shop_id`: the target shop, or null for Me. Any member may move a shop's
        products; into a shop needs membership of it; out to Me only the poster
        or the shop's owner. The listing keeps its photos, expiry and feed
        position. Its chats do NOT move: each open one gets a system message
        (`notice: {notice: "listing_moved", shop_id, name}`) and is closed; the
        buyer starts a new chat with the new seller. Error codes:
        move_not_member (403), move_forbidden (403), shop_unavailable,
        move_same_place, move_has_hold, move_not_movable (422).
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

      let(:record) { create(:listing, :active, user: owner) }
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

      response "422", "cannot move (held, sold, removed, already there)" do
        let(:record) { create(:listing, :reserved, user: owner) }
        run_test! { expect(JSON.parse(response.body)["code"]).to eq("move_has_hold") }
      end

      response "200", "moved" do
        run_test! do |response|
          expect(JSON.parse(response.body)["listing"]["shop"]["id"]).to eq(shop.id)
          expect(record.reload.shop).to eq(shop)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  describe "behaviour" do
    it "moves back to Me with shop_id null" do
      listing = create(:listing, :active, user: owner, shop: shop)
      put "/api/v1/my/listings/#{listing.id}/move", params: { shop_id: nil }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(listing.reload.shop).to be_nil
    end

    it "cannot reach a listing the caller doesn't manage" do
      other = create(:listing, :active)
      put "/api/v1/my/listings/#{other.id}/move", params: { shop_id: shop.id }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    # e5, 1.1.6 run-080: the inbox preview of the notice was its stored body,
    # frozen in the buyer's language at move time ("This listing moved to …"
    # in a Pashto inbox; the seller sees the buyer's language). The row now
    # carries the notice, so each app renders it in the reader's language.
    it "the inbox row carries the notice for both sides; other chats carry null" do
      listing = create(:listing, :active, user: owner)
      buyer = create(:user)
      chat = create(:conversation, listing: listing, buyer: buyer)
      other = create(:conversation, buyer: buyer)
      other.messages.create!(user: buyer, kind: :text, body: "hi")
      put "/api/v1/my/listings/#{listing.id}/move", params: { shop_id: shop.id }, headers: headers, as: :json

      expected = { "notice" => "listing_moved", "shop_id" => shop.id, "name" => "Safi Mobile" }
      get "/api/v1/conversations", headers: auth_headers_for(buyer)
      rows = JSON.parse(response.body)["conversations"].index_by { |r| r["id"] }
      expect(rows[chat.id]["last_message_notice"]).to eq(expected)
      expect(rows[other.id]["last_message_notice"]).to be_nil

      get "/api/v1/conversations", params: { role: "selling" }, headers: headers
      row = JSON.parse(response.body)["conversations"].find { |r| r["id"] == chat.id }
      expect(row["last_message_notice"]).to eq(expected)
    end

    it "the old chat shows the localized-ready notice to both sides, and is closed" do
      listing = create(:listing, :active, user: owner)
      buyer = create(:user)
      chat = create(:conversation, listing: listing, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/move", params: { shop_id: shop.id }, headers: headers, as: :json

      get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(buyer)
      notice = JSON.parse(response.body)["messages"].find { |m| m["kind"] == "system" }
      expect(notice["notice"]).to eq("notice" => "listing_moved", "shop_id" => shop.id, "name" => "Safi Mobile")
      expect(notice["body"]).to include("Safi Mobile")

      post "/api/v1/conversations/#{chat.id}/messages", params: { message: { body: "hello?", kind: "text" } },
                                                        headers: auth_headers_for(buyer), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
