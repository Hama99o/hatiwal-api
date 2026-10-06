require "rails_helper"

# SHOP-3 DoD (API): the seller of every shop chat is the owner; every member
# reads, sends and marks read as the shop; the buyer's payloads (index, show,
# messages, broadcast) name only the shop, for any member's message; pushes go
# to every member but the sender; no personal chat crosses; a buyer's personal
# block on one staff member stops only that member.
RSpec.describe "Shop team chats", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, firstname: "Zarmina", lastname: "Qadirzai") }
  let(:shop) { create(:shop, owner: owner, name: "Herat Silk House") }
  let(:staff) { create(:user, firstname: "Ali", lastname: "Staffkhan").tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:buyer) { create(:user) }
  # A product the STAFF member posted: its chat is still with the owner.
  let(:product) { create(:listing, :active, user: staff, shop: shop) }
  let!(:chat) { Conversations::StartService.new(buyer: buyer, listing: product, message_body: "Salaam").call }

  def json = JSON.parse(response.body)
  def say(user, body) = post("/api/v1/conversations/#{chat.id}/messages", params: { kind: "text", body: body },
                                                                             headers: auth_headers_for(user))

  it "the seller of a shop chat is the owner, whoever posted the product" do
    expect(chat.seller_id).to eq(owner.id)
  end

  it "every member sees it under the shop's Chat tab, reads, sends and marks read as the shop" do
    [ owner, staff ].each do |member|
      get "/api/v1/conversations", params: { shop_id: shop.id }, headers: auth_headers_for(member)
      expect(json["conversations"].pluck("id")).to eq([ chat.id ])
      expect(json["conversations"].first["unread_count"]).to eq(1)
    end

    say(staff, "Yes, we have it")
    expect(response).to have_http_status(:created)
    expect(json["message"]["sender"]).to include("name" => "Herat Silk House", "as_shop" => true)

    put "/api/v1/conversations/#{chat.id}/mark_read", headers: auth_headers_for(owner)
    expect(chat.messages.where(user: buyer, read_at: nil)).to be_empty
    # A teammate's message is never "unread" for the team.
    get "/api/v1/conversations", params: { shop_id: shop.id }, headers: auth_headers_for(owner)
    expect(json["conversations"].first["unread_count"]).to eq(0)
  end

  it "the buyer's index, show, messages and the live broadcast name only the shop, for any member" do
    say(staff, "Welcome")
    reply = chat.messages.last
    headers = auth_headers_for(buyer)
    names = %w[Zarmina Qadirzai Staffkhan]

    [ "/api/v1/conversations", "/api/v1/conversations/#{chat.id}", "/api/v1/conversations/#{chat.id}/messages" ].each do |path|
      get path, headers: headers
      names.each { |n| expect(response.body).not_to include(n), "#{path} leaks #{n}" }
    end
    payload = MessageSerializer.render_as_hash(reply, view: :default)
    expect(payload[:sender]).to include(name: "Herat Silk House")
    expect { BroadcastMessageJob.perform_now(reply.id) }
      .to have_broadcasted_to("conversation_#{chat.id}").with { |d| names.each { |n| expect(d.to_json).not_to include(n) } }
  end

  it "a buyer's message is pushed to every member; a member's reply to the buyer, titled with the shop" do
    [ owner, staff, buyer ].each_with_index { |u, i| u.update!(push_token: "ExponentPushToken[#{i}]") }
    sent = []
    allow(Notifications::ExpoPushService).to receive(:deliver) { |**kw| sent << kw; Struct.new(:error).new(nil) }

    SendMessagePushJob.perform_now(chat.messages.last.id) # the buyer's "Salaam"
    expect(sent.pluck(:token)).to contain_exactly("ExponentPushToken[0]", "ExponentPushToken[1]")

    sent.clear
    reply = chat.messages.create!(user: staff, body: "Hi", kind: :text)
    SendMessagePushJob.perform_now(reply.id)
    expect(sent.map { |s| [ s[:token], s[:title] ] }).to eq([ [ "ExponentPushToken[2]", "Herat Silk House" ] ])
  end

  it "no personal chat crosses: staff never see the owner's, the owner never sees staff's" do
    owner_personal = Conversations::StartService.new(buyer: create(:user), listing: create(:listing, :active, user: owner), message_body: "Hi").call
    staff_personal = Conversations::StartService.new(buyer: create(:user), listing: create(:listing, :active, user: staff), message_body: "Hi").call

    get "/api/v1/conversations", headers: auth_headers_for(staff)
    expect(json["conversations"].pluck("id")).not_to include(owner_personal.id)
    get "/api/v1/conversations/#{owner_personal.id}", headers: auth_headers_for(staff)
    expect(response).to have_http_status(:not_found)
    get "/api/v1/conversations/#{staff_personal.id}", headers: auth_headers_for(owner)
    expect(response).to have_http_status(:not_found)
  end

  it "a buyer's personal block on one staff member stops only that member" do
    create(:block, blocker: buyer, blocked: staff)
    say(staff, "Hello?")
    expect([ response.status, json["code"] ]).to eq([ 422, "blocked_by" ])
    say(owner, "Hello")
    expect(response).to have_http_status(:created)
  end

  it "a block between the buyer and the OWNER ends the chat for the whole team" do
    create(:block, blocker: buyer, blocked: owner)
    say(staff, "Hello?")
    expect(json["code"]).to eq("blocked_by")
  end

  it "a removed member loses the chat at once" do
    shop.remove_team_member!(staff, by: owner)
    say(staff, "Still here?")
    expect(response).to have_http_status(:not_found)
  end

  it "staff can't start a buyer chat on their own shop's product (own_shop)" do
    other_product = create(:listing, :active, user: owner, shop: shop)
    post "/api/v1/listings/#{other_product.id}/conversations", params: { message: "hi" }, headers: auth_headers_for(staff)
    expect(json["code"]).to eq("own_shop")
  end

  it "the live channel's rule (Conversation#participant?) admits members, not outsiders" do
    expect(chat.participant?(staff)).to be(true)
    expect(chat.participant?(create(:user))).to be(false)
  end

  describe "the chat's shop is pinned when it starts (owner rule, 2026-10-06)" do
    it "a PERSONAL chat stays personal when its product later moves into the shop: staff never see it" do
      personal = create(:listing, :active, user: owner)
      personal_chat = Conversations::StartService.new(buyer: buyer, listing: personal, message_body: "Is it yours?").call
      expect(personal_chat.shop_id).to be_nil

      shop.move_listings!(owner, [ personal.id ], to_shop: true)
      expect(personal.reload.shop_id).to eq(shop.id)

      get "/api/v1/conversations", params: { shop_id: shop.id }, headers: auth_headers_for(staff)
      expect(json["conversations"].pluck("id")).not_to include(personal_chat.id)
      get "/api/v1/conversations/#{personal_chat.id}", headers: auth_headers_for(staff)
      expect(response).to have_http_status(:not_found)
      # Only the shop's own chat (the buyer's "Salaam") counts for staff, not this one.
      expect(staff.reload.unread_counts[:shops]).to eq(shop.id.to_s => 1)
      # The owner still has it, as a personal chat (seller = them, no shop face).
      get "/api/v1/conversations/#{personal_chat.id}", headers: auth_headers_for(owner)
      expect(json["conversation"]["shop"]).to be_nil
    end

    it "a chat about a shop product stays the shop's when the product moves out" do
      expect(chat.shop_id).to eq(shop.id)
      shop.move_listings!(staff, [ product.id ], to_shop: false)
      get "/api/v1/conversations", params: { shop_id: shop.id }, headers: auth_headers_for(staff)
      expect(json["conversations"].pluck("id")).to include(chat.id)
    end
  end
end
