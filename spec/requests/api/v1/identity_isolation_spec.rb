require "rails_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 6): messaging must be
# rock solid; identities never mix. Buyer mode, Seller as Me and each shop have
# their own conversations (and their own Support): the inbox, its search, the
# badges and the push target never cross.
RSpec.describe "Identities never mix", type: :request do
  include ActiveJob::TestHelper

  let(:me) { create(:user, firstname: "Tamana", lastname: "Seller") }
  let(:shop_a) { create(:shop, owner: me, name: "Kabul Cosmetics") }
  let(:shop_b) { create(:shop, owner: me, name: "Herat Phones") }
  let(:support) { User.support_account! }
  let(:stranger) { create(:user, firstname: "Basir", lastname: "Buyer") }

  def chat(listing, buyer:) = Conversations::StartService.new(buyer: buyer, listing: listing, message_body: "Salaam").call

  let!(:buying) { chat(create(:listing, :active, title: "Bought lamp"), buyer: me) }
  let!(:selling_me) { chat(create(:listing, :active, user: me, title: "Personal bike"), buyer: stranger) }
  let!(:selling_a) { chat(create(:listing, :active, user: me, shop: shop_a, title: "Cream A"), buyer: stranger) }
  let!(:selling_b) { chat(create(:listing, :active, user: me, shop: shop_b, title: "Phone B"), buyer: stranger) }
  let!(:support_me) { Conversation.support_thread_for!(me).tap { |t| t.messages.create!(user: support, kind: :text, body: "Hello Tamana") } }
  let!(:support_a) { Conversation.shop_support_thread_for!(shop_a).tap { |t| t.messages.create!(user: support, kind: :text, body: "Hello Kabul") } }
  let!(:support_b) { Conversation.shop_support_thread_for!(shop_b).tap { |t| t.messages.create!(user: support, kind: :text, body: "Hello Herat") } }

  def ids(**params)
    get "/api/v1/conversations", params: params, headers: auth_headers_for(me)
    JSON.parse(response.body)["conversations"].pluck("id")
  end

  it "each identity's inbox holds exactly its own chats and its own Support (pinned first)" do
    expect(ids(role: "buying")).to eq([ support_me.id, buying.id ])
    expect(ids(role: "selling", shop_id: "none")).to eq([ support_me.id, selling_me.id ])
    expect(ids(role: "selling", shop_id: shop_a.id)).to eq([ support_a.id, selling_a.id ])
    expect(ids(role: "selling", shop_id: shop_b.id)).to eq([ support_b.id, selling_b.id ])
  end

  it "search stays inside the identity" do
    expect(ids(role: "selling", shop_id: shop_a.id, search: "Phone")).to eq([])
    expect(ids(role: "selling", shop_id: shop_a.id, search: "Hello")).to eq([ support_a.id ])
    expect(ids(role: "buying", search: "Cream")).to eq([])
    expect(ids(role: "selling", shop_id: "none", search: "Hello")).to eq([ support_me.id ])
  end

  it "badges count each identity apart" do
    [ buying, selling_me, selling_a, selling_b ].each do |c|
      other = c.buyer_id == me.id ? c.seller : c.buyer
      c.messages.create!(user: other, kind: :text, body: "Unread")
    end
    get "/api/v1/users/me", headers: auth_headers_for(me)
    counts = JSON.parse(response.body)["user"]["unread_counts"]
    # The Salaam that opened each selling chat is unread too (the buyer's).
    expect(counts).to include("buying" => 2, "selling_me" => 2, "support" => 1)
    expect(counts["shops"]).to eq(shop_a.id.to_s => 3, shop_b.id.to_s => 3)
  end

  it "a push names the identity to open: buying, or selling + the shop" do
    pushes = []
    allow(Notifications::ExpoPushService).to receive(:deliver) do |**args|
      pushes << args[:data]
      Struct.new(:error).new(nil)
    end
    me.update_columns(push_token: "ExponentPushToken[me]")
    [ buying, selling_a ].each do |c|
      other = c.buyer_id == me.id ? c.seller : c.buyer
      SendMessagePushJob.perform_now(c.messages.create!(user: other, kind: :text, body: "Ping").id)
    end
    SendMessagePushJob.perform_now(support_b.messages.create!(user: support, kind: :text, body: "Ping").id)

    expect(pushes).to contain_exactly(
      include(conversationId: buying.id, role: "buying", shopId: nil),
      include(conversationId: selling_a.id, role: "selling", shopId: shop_a.id),
      include(conversationId: support_b.id, role: "selling", shopId: shop_b.id)
    )
  end
end
