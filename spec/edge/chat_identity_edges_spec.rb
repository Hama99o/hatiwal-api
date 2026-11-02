require "rails_helper"

# Edge pass 1.1.6 (hatiwal-d0, 2026-10-08) — who a shop chat's messages are
# from, after the team changes. What a teammate wrote AS the shop stays the
# shop's: a member leaving must not turn it back into their personal name for
# the buyer, nor into "unread" for the rest of the team.
RSpec.describe "Shop chat identity — edge cases", type: :request do
  include ActiveJob::TestHelper

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
    json["messages"]
  end

  def unread_for(user)
    get "/api/v1/conversations", params: { shop_id: shop.id }, headers: auth_headers_for(user)
    json["conversations"].find { |c| c["id"] == chat.id }&.fetch("unread_count")
  end

  shared_examples "the shop keeps what the member wrote" do
    before do
      say(staff, "Yes, we have it in blue")
      put "/api/v1/conversations/#{chat.id}/mark_read", headers: auth_headers_for(owner)
      gone.call
    end

    it "the buyer still sees the shop, never the former member's name" do
      reply = messages_as(buyer).find { |m| m["body"] == "Yes, we have it in blue" }
      expect(reply["sender"]).to include("name" => "Herat Silk House", "as_shop" => true)
      expect(reply).not_to have_key("sent_by")
      get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(buyer)
      expect(response.body).not_to include("Staffkhan")
      get "/api/v1/conversations", headers: auth_headers_for(buyer)
      expect(response.body).not_to include("Staffkhan")
    end

    it "the team still sees it as the shop's, replied by the former member" do
      reply = messages_as(owner).find { |m| m["body"] == "Yes, we have it in blue" }
      expect(reply["sender"]).to include("as_shop" => true)
      expect(reply["sent_by"]).to include("id" => staff.id)
    end

    it "it does not become unread for the rest of the team" do
      expect(unread_for(owner)).to eq(0)
      get "/api/v1/users/me", headers: auth_headers_for(owner)
      expect(json["user"]["unread_counts"]["shops"].to_h.fetch(shop.id.to_s, 0)).to eq(0)
    end
  end

  context "the member leaves" do
    let(:gone) { -> { shop.leave!(staff) } }

    it_behaves_like "the shop keeps what the member wrote"
  end

  context "the member is removed" do
    let(:gone) { -> { shop.remove_team_member!(staff, by: owner) } }

    it_behaves_like "the shop keeps what the member wrote"
  end

  it "a buyer's message after a member left is pushed to the current team only" do
    staff
    shop.leave!(staff)
    recipients = SendMessagePushJob.new.send(:recipients, chat.reload, buyer)
    expect(recipients.map(&:id)).to eq([ owner.id ])
  end

  it "a suspended shop's chats still name the shop to the buyer, never the owner or a member" do
    say(staff, "Yes, we have it in blue")
    say(owner, "Come by after 4")
    shop.update_columns(status: Shop.statuses[:suspended])
    %W[/api/v1/conversations /api/v1/conversations/#{chat.id} /api/v1/conversations/#{chat.id}/messages].each do |path|
      get path, headers: auth_headers_for(buyer)
      %w[Zarmina Qadirzai Staffkhan].each { |n| expect(response.body).not_to include(n), "#{path} leaks #{n}" }
    end
  end

  describe "a listing that moves away and comes back" do
    it "Me (Staff) -> shop -> Me (a manager): the buyer's new chat reaches the manager, not the old poster" do
      manager = create(:user, firstname: "Mina", lastname: "Managerzai").tap { |u| shop.shop_members.create!(user: u, role: :manager) }
      personal = create(:listing, :active, user: staff)
      old = Conversations::StartService.new(buyer: buyer, listing: personal, message_body: "Hi Ali").call
      Listings::MoveService.new(listing: personal, actor: staff, shop_id: shop.id).call
      Listings::MoveService.new(listing: personal.reload, actor: manager, shop_id: nil).call
      expect(old.reload).to be_closed

      fresh = Conversations::StartService.new(buyer: buyer, listing: personal.reload, message_body: "Still for sale?").call
      expect(fresh.seller_id).to eq(manager.id)
      expect(fresh.id).not_to eq(old.id)
      expect(old.reload).to be_closed # the old thread with Ali stays Ali's, read-only
    end

    it "shop -> Me -> the same shop: the shop's old chat with the buyer reopens with the shop" do
      Listings::MoveService.new(listing: product, actor: owner, shop_id: nil).call
      Listings::MoveService.new(listing: product.reload, actor: owner, shop_id: shop.id).call
      again = Conversations::StartService.new(buyer: buyer, listing: product.reload, message_body: "Back?").call
      expect(again.id).to eq(chat.id)
      expect(again.reload).to be_open
    end

    it "the reopen path still refuses a buyer the seller has blocked" do
      Listings::MoveService.new(listing: product, actor: owner, shop_id: nil).call
      Listings::MoveService.new(listing: product.reload, actor: owner, shop_id: shop.id).call
      Block.create!(blocker: owner, blocked: buyer)
      expect { Conversations::StartService.new(buyer: buyer, listing: product.reload, message_body: "Back?").call }
        .to raise_error(Conversations::StartService::Error)
      expect(chat.reload).to be_closed
    end
  end

  describe "a suspended shop's product chats are readable but shut, like its Message-shop chats" do
    before { shop.suspend! }

    it "neither the buyer nor the team can send; reading still works" do
      [ buyer, owner ].each do |user|
        post "/api/v1/conversations/#{chat.id}/messages", params: { kind: "text", body: "Hello?" }, headers: auth_headers_for(user)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json["code"]).to eq("shop_unavailable")
        get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(user)
        expect(response).to have_http_status(:ok)
      end
    end

    it "reactivated: the chat works again" do
      shop.update!(status: :active)
      say(buyer, "Hello again")
    end

    it "a CLOSED shop's product chat is the owner's now: the buyer and the owner still talk" do
      shop.update!(status: :active)
      shop.close!
      say(buyer, "Still there?")
      say(owner, "Yes, personally")
    end
  end

  describe "a CLOSED shop's product chats are the owner's own now" do
    before do
      shop.close!
      say(buyer, "Do you still sell it?")
    end

    it "they are in the owner's Seller-as-Me inbox" do
      get "/api/v1/conversations", params: { role: "selling", shop_id: "none" }, headers: auth_headers_for(owner)
      expect(json["conversations"].pluck("id")).to include(chat.id)
    end

    it "a buyer coming back to the product (now the owner's own) continues the same chat, never a second one" do
      again = Conversations::StartService.new(buyer: buyer, listing: product.reload, message_body: "Still for sale?").call
      expect(again.id).to eq(chat.id)
      expect(Conversation.where(listing_id: product.id, buyer_id: buyer.id).count).to eq(1)
    end

    it "their unread count is the owner's Me count, not a shop's the app no longer lists" do
      owner.reload
      expect(owner.unread_counts).to include(selling_me: 2)
      expect(owner.unread_counts[:shops]).not_to have_key(shop.id.to_s)
    end
  end

  describe "the matrix: transitions while a chat is open" do
    it "an ownership transfer: the new owner is the seller, the old owner (a manager now) still reads it, nothing becomes unread" do
      say(staff, "We have it")
      put "/api/v1/conversations/#{chat.id}/mark_read", headers: auth_headers_for(owner)
      shop.transfer_ownership!(staff, by: owner)
      expect(chat.reload.seller_id).to eq(staff.id)
      [ owner, staff ].each { |member| expect(unread_for(member)).to eq(0) }
      reply = messages_as(buyer).find { |m| m["body"] == "We have it" }
      expect(reply["sender"]).to include("name" => "Herat Silk House", "as_shop" => true)
      say(owner, "Still here as a manager")
    end

    it "the shop is renamed: every message, old and new, shows the new name" do
      say(owner, "Hello")
      shop.update!(name: "Herat Silk & Co")
      expect(messages_as(buyer).select { |m| m["sender"]["as_shop"] }.map { |m| m["sender"]["name"] }.uniq).to eq([ "Herat Silk & Co" ])
    end

    it "the listing is removed (deleted / taken down): the chat stays readable, still the shop's" do
      say(owner, "Hello")
      product.update_columns(removed_at: Time.current, removed_reason: "seller_deleted")
      get "/api/v1/conversations/#{chat.id}", headers: auth_headers_for(buyer)
      expect(response).to have_http_status(:ok)
      expect(json["conversation"]["listing_deleted"]).to be(true)
      expect(response.body).not_to include("Qadirzai")
      expect(messages_as(buyer).find { |m| m["body"] == "Hello" }["sender"]).to include("as_shop" => true)
    end

    it "the buyer deletes their account: the team keeps the thread, the buyer shows as a deleted user, no push goes out" do
      say(buyer, "One more question")
      buyer.anonymize_account!
      get "/api/v1/conversations/#{chat.id}", headers: auth_headers_for(owner)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Buyerzai")
      expect(SendMessagePushJob.new.send(:recipients, chat.reload, owner).map(&:id)).to eq([ buyer.id ])
      expect(buyer.reload.push_token).to be_nil # deliver() returns on a blank token
    end

    it "a push from the shop to the buyer: titled with the shop, routed to Buying; the buyer's to the team: routed to that shop" do
      [ owner, staff, buyer ].each { |u| u.update_columns(push_token: "ExponentPushToken[#{u.id}]") }
      sent = []
      allow(Notifications::ExpoPushService).to receive(:deliver) { |**kw| sent << kw; Struct.new(:error).new(nil) }
      say(staff, "Yes")
      perform_enqueued_jobs(only: SendMessagePushJob)
      to_buyer = sent.find { |p| p[:token] == "ExponentPushToken[#{buyer.id}]" }
      expect(to_buyer).to include(title: "Herat Silk House")
      expect(to_buyer[:data]).to include(role: "buying", shopId: shop.id)

      sent.clear
      say(buyer, "Great")
      perform_enqueued_jobs(only: SendMessagePushJob)
      expect(sent.map { |p| p[:token] }).to contain_exactly("ExponentPushToken[#{owner.id}]", "ExponentPushToken[#{staff.id}]")
      expect(sent.map { |p| p[:data] }).to all(include(role: "selling", shopId: shop.id))
    end
  end

  # P0 privacy (docs audit 1.1.6, d0): the privacy text promises a buyer never
  # learns which member wrote. A member's user id let any buyer read their name
  # and photo from the guest-readable public profile.
  describe "a message written as the shop carries no member id for the buyer" do
    before { say(staff, "Yes, in blue") }

    it "REST: the buyer gets sender.id null; the team keeps it (alignment, replied by)" do
      reply = messages_as(buyer).find { |m| m["body"] == "Yes, in blue" }
      expect(reply["sender"]).to include("id" => nil, "as_shop" => true, "name" => "Herat Silk House")
      mine = messages_as(staff).find { |m| m["body"] == "Yes, in blue" }
      expect(mine["sender"]["id"]).to eq(staff.id)
      expect(messages_as(owner).find { |m| m["body"] == "Yes, in blue" }["sender"]["id"]).to eq(staff.id)
    end

    it "the live streams: the public (buyer's) one without the id, the team's with it" do
      reply = chat.messages.find_by(body: "Yes, in blue")
      expect(MessageSerializer.render_as_hash(reply, view: :default)[:sender][:id]).to be_nil
      expect(MessageSerializer.render_as_hash(reply, view: :default, team: true)[:sender][:id]).to eq(staff.id)
    end

    it "the buyer's own messages keep their id (their own alignment)" do
      expect(messages_as(buyer).find { |m| m["body"] == "Salaam" }["sender"]["id"]).to eq(buyer.id)
    end
  end

  # P0 privacy (d0, 2026-10-08): the public shop page (guest-readable) named the
  # OWNER — `owner: {id, name: full_name}` in the :public view. The privacy text
  # promises buyers never see the owner's personal name.
  describe "the public shop page never names the owner" do
    it "a guest and a buyer: no owner block, no owner name anywhere" do
      get "/api/v1/shops/#{shop.id}"
      expect(response).to have_http_status(:ok)
      expect(json["shop"]).not_to have_key("owner")
      expect(response.body).not_to include("Qadirzai")

      get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(buyer)
      expect(json["shop"]).not_to have_key("owner")
      expect(response.body).not_to include("Qadirzai")
    end

    it "the team still gets it" do
      get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(staff)
      expect(json["shop"]["owner"]).to include("id" => owner.id)
    end
  end
end
