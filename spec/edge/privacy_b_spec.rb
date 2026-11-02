require "rails_helper"

# privacy-b (d0, 2026-10-08; owner decides at 09:00 on 2026-10-09): a buyer on
# a 1.1.7+ client never receives the user id of the person behind a shop. Any
# id opens the guest-readable public profile (name, photo). The shop's team and
# clients older than 1.1.7 (no / older X-App-Version, not web) keep the owner
# id, so store apps that predate shops do not break. Blocking and reporting a
# shop go by the SHOP's id.
RSpec.describe "privacy-b: no owner id in what a buyer sees of a shop", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, firstname: "Zarmina", lastname: "Qadirzai") }
  let(:shop) { create(:shop, owner: owner, name: "Herat Silk House") }
  let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:buyer) { create(:user) }
  let(:product) { create(:listing, :active, user: owner, shop: shop) }
  let!(:chat) { Conversations::StartService.new(buyer: buyer, listing: product, message_body: "Salaam").call }

  NEW_APP = { "X-App-Version" => "1.1.7", "X-App-Platform" => "android" }.freeze
  WEB = { "X-App-Platform" => "web" }.freeze
  # The SHIPPED 1.1.6 build has no privacy-b client code: it must keep the owner id.
  OLD_APP = { "X-App-Version" => "1.1.6", "X-App-Platform" => "android" }.freeze

  def json = JSON.parse(response.body)
  def as(user, client = NEW_APP) = auth_headers_for(user).merge(client)

  describe "the listing's seller block" do
    it "a buyer on 1.1.7 / web: the shop with shop_id, no owner id (detail and list)" do
      [ NEW_APP, WEB ].each do |client|
        get "/api/v1/listings/#{product.id}", headers: as(buyer, client)
        expect(json["listing"]["seller"]).to include("id" => nil, "shop_id" => shop.id, "as_shop" => true, "name" => "Herat Silk House")

        get "/api/v1/listings", params: { shop_id: shop.id }, headers: as(buyer, client)
        row = json["listings"].find { |l| l["id"] == product.id }
        expect(row["seller"]).to include("id" => nil, "shop_id" => shop.id) if row
      end
    end

    it "a guest on the web: no owner id either" do
      get "/api/v1/listings/#{product.id}", headers: WEB
      expect(json["listing"]["seller"]["id"]).to be_nil
    end

    it "the shop's team keeps the owner id (own-listing checks)" do
      get "/api/v1/listings/#{product.id}", headers: as(staff)
      expect(json["listing"]["seller"]["id"]).to eq(owner.id)
    end

    it "an app older than 1.1.7, or one without the header, keeps the owner id (it predates shops)" do
      [ OLD_APP, {} ].each do |client|
        get "/api/v1/listings/#{product.id}", headers: auth_headers_for(buyer).merge(client)
        expect(json["listing"]["seller"]["id"]).to eq(owner.id)
      end
    end
  end

  describe "the conversation's seller / other participant" do
    it "the buyer on 1.1.7: the shop face, no owner id; the team: the owner id" do
      get "/api/v1/conversations/#{chat.id}", headers: as(buyer)
      c = json["conversation"]
      expect(c["other_participant"]).to include("id" => nil, "shop_id" => shop.id, "as_shop" => true)
      expect(c["seller"]).to include("id" => nil, "shop_id" => shop.id) if c["seller"]

      get "/api/v1/conversations", headers: as(buyer)
      row = json["conversations"].find { |x| x["id"] == chat.id }
      expect(row["other_participant"]).to include("id" => nil, "shop_id" => shop.id)

      get "/api/v1/conversations/#{chat.id}", headers: as(staff)
      expect(json["conversation"]["seller"]["id"]).to eq(owner.id) if json["conversation"]["seller"]
    end

    it "an old app keeps the owner id" do
      get "/api/v1/conversations/#{chat.id}", headers: auth_headers_for(buyer).merge(OLD_APP)
      expect(json["conversation"]["other_participant"]["id"]).to eq(owner.id)
    end

    it "nothing a buyer gets names the owner" do
      [ "/api/v1/conversations", "/api/v1/conversations/#{chat.id}", "/api/v1/listings/#{product.id}" ].each do |path|
        get path, headers: as(buyer)
        expect(response.body).not_to include("Qadirzai")
        expect(response.body).not_to match(/"id":#{owner.id}[,}]/) if path.include?("listings")
      end
    end
  end

  describe "block a shop by its id" do
    it "blocks the owner underneath: the chat is shut both ways, exactly like a person block" do
      post "/api/v1/shops/#{shop.id}/block", headers: as(buyer)
      expect(response).to have_http_status(:no_content)
      expect(buyer.blocked?(owner)).to be(true)

      post "/api/v1/conversations/#{chat.id}/messages", params: { kind: "text", body: "hi" }, headers: as(buyer)
      expect(response.status).to be_in([ 403, 422 ])
    end

    it "the blocked list shows the SHOP, never the owner; unblock by the shop's id" do
      post "/api/v1/shops/#{shop.id}/block", headers: as(buyer)
      get "/api/v1/blocks", headers: as(buyer)
      expect(response.body).not_to include("Qadirzai")
      entry = json["users"]&.first || json["blocks"]&.first
      expect(entry).to include("id" => nil, "shop_id" => shop.id, "as_shop" => true, "name" => "Herat Silk House")

      delete "/api/v1/shops/#{shop.id}/block", headers: as(buyer)
      expect(response).to have_http_status(:no_content)
      expect(buyer.reload.blocked?(owner)).to be(false)
    end

    it "an old app's blocked list keeps the person (it can only unblock by user id)" do
      post "/api/v1/shops/#{shop.id}/block", headers: as(buyer)
      get "/api/v1/blocks", headers: auth_headers_for(buyer).merge(OLD_APP)
      entry = json["users"]&.first || json["blocks"]&.first
      expect(entry["id"]).to eq(owner.id)
    end

    it "a member cannot block their own shop; a closed shop cannot be blocked" do
      post "/api/v1/shops/#{shop.id}/block", headers: as(staff)
      expect(response).to have_http_status(:forbidden)
      shop.close!
      post "/api/v1/shops/#{shop.id}/block", headers: as(buyer)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "report a shop by its id" do
    it "a buyer reports the shop; its team cannot" do
      post "/api/v1/reports", params: { report: { reportable_type: "Shop", reportable_id: shop.id, reason: "fraud" } }, headers: as(buyer)
      expect(response).to have_http_status(:created)
      expect(Report.last).to have_attributes(reportable_type: "Shop", reportable_id: shop.id)

      post "/api/v1/reports", params: { report: { reportable_type: "Shop", reportable_id: shop.id, reason: "fraud" } }, headers: as(staff)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "only known types can be reported" do
      post "/api/v1/reports", params: { report: { reportable_type: "AdminUser", reportable_id: 1, reason: "fraud" } }, headers: as(buyer)
      expect(response.status).to be_in([ 403, 422 ])
    end
  end
end
