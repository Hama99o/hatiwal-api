require "rails_helper"

# Owner, 2026-10-07: ONE Support thread per person, written from any mode or
# shop; every user message records where it was written from, for the admin.
RSpec.describe "Support message context", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, firstname: "Gul", lastname: "Seller") }
  let(:shop) { create(:shop, owner: user, name: "Gul Cosmetics") }
  let(:thread) { Conversation.support_thread_for!(user) }

  def send_support(context, as: user)
    post "/api/v1/conversations/#{thread.id}/messages", params: { body: "Salaam", context: context }.compact.to_json,
                                                        headers: auth_headers_for(as).merge("Content-Type" => "application/json")
  end

  def json = JSON.parse(response.body)

  it "stores buyer, seller (Me) and a shop with the sender's role" do
    send_support({ mode: "buyer" })
    send_support({ mode: "seller" })
    send_support({ mode: "seller", shop_id: shop.id })
    expect(response).to have_http_status(:created)
    expect(thread.messages.order(:id).pluck(:context)).to eq([
      { "mode" => "buyer" }, { "mode" => "seller" }, { "mode" => "seller", "shop_id" => shop.id, "role" => "owner" }
    ])
  end

  it "a staff member writing as the shop writes in THEIR OWN thread, labelled with their role" do
    staff = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    own = Conversation.support_thread_for!(staff)
    post "/api/v1/conversations/#{own.id}/messages", params: { body: "Hi", context: { mode: "seller", shop_id: shop.id } }.to_json,
                                                     headers: auth_headers_for(staff).merge("Content-Type" => "application/json")
    expect(own.messages.last.context).to include("shop_id" => shop.id, "role" => "staff")
    expect(thread.messages).to be_empty # never the owner's thread
  end

  it "refuses a shop the sender is not in, a shop as buyer, and an unknown mode (422, coded)" do
    other = create(:shop)
    [ { mode: "seller", shop_id: other.id }, { mode: "buyer", shop_id: shop.id }, { mode: "admin" } ].each do |ctx|
      send_support(ctx)
      expect(response).to have_http_status(:unprocessable_entity), ctx.inspect
      expect(json["code"]).to eq("invalid_message_context")
    end
    expect(thread.messages).to be_empty
  end

  it "an older app sends no context: accepted, stored as nil" do
    send_support(nil)
    expect(response).to have_http_status(:created)
    expect(thread.messages.last.context).to be_nil
  end

  it "a context sent in a listing chat is ignored, never stored" do
    buyer = create(:user)
    chat = Conversations::StartService.new(buyer: buyer, listing: create(:listing, :active, user: user), message_body: "Hi").call
    post "/api/v1/conversations/#{chat.id}/messages", params: { body: "Still there?", context: { mode: "buyer" } }.to_json,
                                                      headers: auth_headers_for(buyer).merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:created)
    expect(chat.messages.last.context).to be_nil
  end

  describe "the admin thread view" do
    let(:admin) { create(:admin_user) }

    it "shows where each user message was written from, with a shop link; unknown for older apps" do
      send_support({ mode: "buyer" })
      send_support({ mode: "seller" })
      send_support({ mode: "seller", shop_id: shop.id })
      send_support(nil)

      sign_in admin, scope: :admin_user
      get admin_support_conversation_path(thread)
      body = response.body
      expect(body).to include("as buyer", "as seller (Me)", "unknown (older app)")
      expect(body).to include(%(href="#{admin_shop_path(shop)}">Gul Cosmetics</a> (Owner)))
    end
  end
end
