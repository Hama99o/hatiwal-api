require "rails_helper"

# Support message context: where a user message in a Support thread was written
# from, for the admin. Owner, 2026-10-12: Support is per identity, so a person's
# own thread records Buyer mode or Seller as Me, and a shop writes in its OWN
# thread (spec/requests/api/v1/support_per_identity_spec.rb), never in a person's.
RSpec.describe "Support message context", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, firstname: "Gul", lastname: "Seller") }
  let(:shop) { create(:shop, owner: user, name: "Gul Cosmetics") }
  let(:thread) { Conversation.support_thread_for!(user) }

  def send_support(context, as: user, to: thread)
    post "/api/v1/conversations/#{to.id}/messages", params: { body: "Salaam", context: context }.compact.to_json,
                                                    headers: auth_headers_for(as).merge("Content-Type" => "application/json")
  end

  def json = JSON.parse(response.body)

  it "a person's thread stores Buyer mode and Seller as Me" do
    send_support({ mode: "buyer" })
    send_support({ mode: "seller" })
    expect(response).to have_http_status(:created)
    expect(thread.messages.order(:id).pluck(:context)).to eq([ { "mode" => "buyer" }, { "mode" => "seller" } ])
  end

  it "refuses a shop in a person's thread (a shop has its own), and an unknown mode (422, coded)" do
    [ { mode: "seller", shop_id: shop.id }, { mode: "admin" } ].each do |ctx|
      send_support(ctx)
      expect(response).to have_http_status(:unprocessable_entity), ctx.inspect
      expect(json["code"]).to eq("invalid_message_context")
    end
    expect(thread.messages).to be_empty
  end

  it "a shop's thread stamps the member and role itself, whatever the app sends" do
    staff = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    shop_thread = Conversation.shop_support_thread_for!(shop)
    send_support({ mode: "buyer" }, as: staff, to: shop_thread)
    expect(response).to have_http_status(:created)
    expect(shop_thread.messages.last.context).to eq("mode" => "seller", "shop_id" => shop.id, "role" => "staff")
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

    it "a person's thread: where each message was written from; unknown for older apps" do
      send_support({ mode: "buyer" })
      send_support({ mode: "seller" })
      send_support(nil)

      sign_in admin, scope: :admin_user
      get admin_support_conversation_path(thread)
      expect(response.body).to include("as buyer", "as seller (Me)", "unknown (older app)")
    end
  end
end
