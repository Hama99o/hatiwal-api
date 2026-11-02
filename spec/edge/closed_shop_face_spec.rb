require "rails_helper"

# Side branch `closed-shop-face` (d0, 2026-10-08; the owner chooses at 09:00 on
# 2026-10-09). When a shop CLOSES, its product chats go back to the owner. Until
# now that also rewrote the PAST: every message the team had written as the shop
# showed the buyer the writer's personal name (the owner's, or a former staff
# member's). Here what was written as the shop stays the shop's — its name,
# marked closed — and only what the owner writes AFTER the closure is personal.
RSpec.describe "A closed shop's chats keep what was written as the shop", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:owner) { create(:user, firstname: "Zarmina", lastname: "Qadirzai") }
  let(:shop) { create(:shop, owner: owner, name: "Herat Silk House") }
  let(:staff) { create(:user, firstname: "Ali", lastname: "Staffkhan").tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:buyer) { create(:user, firstname: "Bilal", lastname: "Buyerzai") }
  let(:product) { create(:listing, :active, user: owner, shop: shop) }
  let!(:chat) { Conversations::StartService.new(buyer: buyer, listing: product, message_body: "Salaam").call }

  def json = JSON.parse(response.body)
  def say(user, body)
    post "/api/v1/conversations/#{chat.id}/messages", params: { kind: "text", body: body }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:created)
  end

  def messages_as(user)
    get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(user)
    json["messages"].index_by { |m| m["body"] }
  end

  before do
    say(staff, "Yes, in blue")
    say(owner, "Come after 4")
    travel 1.minute
    shop.close!
    travel 1.minute
    say(owner, "The shop closed, I still have it at home")
  end

  it "records when the shop closed" do
    expect(shop.reload.closed_at).to be_present
  end

  it "the buyer: messages written before the closure keep the shop's name, marked closed — no personal name, no member id" do
    m = messages_as(buyer)
    [ "Yes, in blue", "Come after 4" ].each do |body|
      expect(m[body]["sender"]).to include("name" => "Herat Silk House", "as_shop" => true, "shop_closed" => true, "id" => nil)
    end
    expect(response.body).not_to include("Staffkhan")
  end

  it "the buyer: what the owner writes after the closure is from the owner personally" do
    sender = messages_as(buyer)["The shop closed, I still have it at home"]["sender"]
    expect(sender).to include("name" => "Zarmina Qadirzai")
    expect(sender).not_to have_key("as_shop")
  end

  it "the owner still sees who on the team wrote each shop message" do
    m = messages_as(owner)
    expect(m["Yes, in blue"]["sender"]).to include("as_shop" => true, "shop_closed" => true, "id" => staff.id)
    expect(m["Yes, in blue"]["sent_by"]).to include("id" => staff.id)
  end

  it "the conversation says the shop closed (for the composer note), on both sides" do
    [ buyer, owner ].each do |user|
      get "/api/v1/conversations/#{chat.id}", headers: auth_headers_for(user)
      expect(json["conversation"]["closed_shop"]).to include("name" => "Herat Silk House")
      expect(json["conversation"]["closed_shop"]["closed_at"]).to be_present
    end
  end

  it "an open shop's chat has no closed_shop and no shop_closed marks" do
    other = create(:shop, owner: create(:user))
    item = create(:listing, :active, user: other.owner, shop: other)
    c = Conversations::StartService.new(buyer: buyer, listing: item, message_body: "Hi").call
    get "/api/v1/conversations/#{c.id}", headers: auth_headers_for(buyer)
    expect(json["conversation"]["closed_shop"]).to be_nil
  end
end
