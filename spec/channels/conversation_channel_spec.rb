require "rails_helper"

# SHOP-3: the server picks the stream per subscriber. A shop chat's team gets
# the members-only stream (messages + `sent_by`); the buyer the plain one.
RSpec.describe ConversationChannel, type: :channel do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:buyer) { create(:user) }
  let(:chat) { Conversations::StartShopService.new(buyer: buyer, shop: shop, message_body: "Hi").call }

  it "puts the shop's team on the team stream" do
    [ owner, staff ].each do |member|
      stub_connection current_user: member
      subscribe conversation_id: chat.id
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("conversation_#{chat.id}_team")
      expect(subscription).not_to have_stream_from("conversation_#{chat.id}")
    end
  end

  it "keeps the buyer on the plain stream" do
    stub_connection current_user: buyer
    subscribe conversation_id: chat.id
    expect(subscription).to have_stream_from("conversation_#{chat.id}")
    expect(subscription).not_to have_stream_from("conversation_#{chat.id}_team")
  end

  it "a personal chat stays on the plain stream for both sides" do
    personal = Conversations::StartService.new(buyer: buyer, listing: create(:listing, :active, user: owner), message_body: "Hi").call
    stub_connection current_user: owner
    subscribe conversation_id: personal.id
    expect(subscription).to have_stream_from("conversation_#{personal.id}")
  end

  it "rejects an outsider" do
    stub_connection current_user: create(:user)
    subscribe conversation_id: chat.id
    expect(subscription).to be_rejected
  end
end
