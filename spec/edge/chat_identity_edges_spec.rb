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
end
