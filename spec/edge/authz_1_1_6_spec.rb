require "rails_helper"

# Authorization / IDOR sweep of every endpoint added or changed in 1.1.6
# (2026-10-08). Shop A's owner, manager and staff own the resources; five
# outsiders try them with A's ids: a stranger, a buyer who chats with A, staff
# of ANOTHER shop, a member A removed, and a guest. Every attempt must be
# refused (401 for the guest; 403/404 otherwise) and change nothing.
# The table of endpoint × actor → status is written to tmp/authz_1_1_6.md.
# Namespaced: a constant defined in a describe block is global, and RESULTS
# collided with spec/perf's in a full run.
module Authz116
  ACTORS = %i[stranger buyer other_staff removed guest].freeze
  RESULTS = []
end

RSpec.describe "1.1.6 authorization sweep", type: :request do
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  let!(:shop)    { create(:shop, :verification_eligible) }
  let!(:owner)   { shop.owner }
  let!(:manager) { create(:user, :confirmed).tap { |u| shop.shop_members.create!(user: u, role: :manager) } }
  let!(:staff)   { create(:user, :confirmed).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let!(:removed) do
    create(:user, :confirmed).tap do |u|
      shop.shop_members.create!(user: u, role: :staff)
      shop.remove_team_member!(u, by: owner)
    end
  end
  let!(:stranger) { create(:user, :confirmed) }
  let!(:buyer)    { create(:user, :confirmed) }
  let!(:other_staff) do
    create(:user, :confirmed).tap { |u| create(:shop).shop_members.create!(user: u, role: :staff) }
  end

  let!(:product) { create(:listing, :active, user: staff, shop: shop, expires_at: 2.days.ago) }
  let!(:invite)  { create(:shop_invite, shop: shop) }
  let!(:request_) do
    create(:shop_verification_request, shop: shop, requested_by: manager, name_on_document: manager.full_name)
  end
  let!(:shop_chat) do
    Conversation.create!(listing: product, shop_id: shop.id, buyer: buyer, seller: owner).tap do |c|
      c.messages.create!(user: buyer, body: "Still there?", kind: :text)
    end
  end
  let!(:support) { Conversation.shop_support_thread_for!(shop) }
  let(:others_listing) { create(:listing, :active, user: stranger) }

  after(:all) do
    rows = Authz116::RESULTS.group_by(&:first).map do |label, hits|
      "| #{label} | " + Authz116::ACTORS.map { |a| hits.find { |h| h[1] == a }&.last || "—" }.join(" | ") + " |"
    end
    File.write(Rails.root.join("tmp/authz_1_1_6.md"),
               ([ "| endpoint | #{Authz116::ACTORS.join(' | ')} |", "|---|#{'---|' * Authz116::ACTORS.size}" ] + rows).join("\n") + "\n")
  end

  def headers_for(actor)
    actor == :guest ? {} : public_send(actor).create_new_auth_token
  end

  def attempt(label, verb, path, actor, params: {})
    public_send(verb, path, params: params, headers: headers_for(actor), as: :json)
    Authz116::RESULTS << [ label, actor, response.status ]
    allowed = actor == :guest ? [ 401 ] : [ 403, 404 ]
    # Selling as a shop you're not on: the documented 422 cannot_sell_as_shop.
    allowed += [ 422 ] if label == "PATCH selling_as shop" && response.parsed_body["code"] == "cannot_sell_as_shop"
    expect(allowed).to include(response.status), "#{label} as #{actor}: #{response.status} #{response.body.first(160)}"
  end

  # Every member-only endpoint, with shop A's ids.
  def endpoints
    s = shop.id
    [
      [ "GET members", :get, "/api/v1/shops/#{s}/members" ],
      [ "PATCH member role", :patch, "/api/v1/shops/#{s}/members/#{staff.id}", { role: "manager" } ],
      [ "DELETE member", :delete, "/api/v1/shops/#{s}/members/#{staff.id}" ],
      [ "DELETE membership (leave)", :delete, "/api/v1/shops/#{s}/membership" ],
      [ "POST transfer", :post, "/api/v1/shops/#{s}/transfer", { user_id: staff.id } ],
      [ "GET invites", :get, "/api/v1/shops/#{s}/invites" ],
      [ "POST invite", :post, "/api/v1/shops/#{s}/invites", {} ],
      [ "DELETE invite", :delete, "/api/v1/shops/#{s}/invites/#{invite.id}" ],
      [ "POST invite resend", :post, "/api/v1/shops/#{s}/invites/#{invite.id}/resend" ],
      [ "PATCH shop", :patch, "/api/v1/shops/#{s}", { shop: { name: "Taken over" } } ],
      [ "DELETE shop (close)", :delete, "/api/v1/shops/#{s}" ],
      [ "POST move_listings", :post, "/api/v1/shops/#{s}/move_listings", { listing_ids: [ others_listing.id ] } ],
      [ "POST verification (shop)", :post, "/api/v1/verification_requests",
        { subject: "shop:#{s}", verification_request: { document_type: "e_tazkira", name_on_document: "X Y", document_number: "1234564821" } } ],
      [ "DELETE verification", :delete, "/api/v1/verification_requests/#{request_.id}" ],
      [ "POST support_conversation?shop_id", :post, "/api/v1/support_conversation?shop_id=#{s}" ],
      [ "GET shop Support thread", :get, "/api/v1/conversations/#{support.id}" ],
      [ "GET shop Support messages", :get, "/api/v1/conversations/#{support.id}/messages" ],
      [ "PUT renew (shop product)", :put, "/api/v1/my/listings/#{product.id}/renew" ],
      [ "PUT relaunch (shop product)", :put, "/api/v1/my/listings/#{product.id}/relaunch" ],
      [ "PUT move (shop product)", :put, "/api/v1/my/listings/#{product.id}/move", { shop_id: nil } ],
      [ "POST duplicate (shop product)", :post, "/api/v1/my/listings/#{product.id}/duplicate", { shop_id: nil } ],
      [ "GET listing analytics", :get, "/api/v1/my/listings/#{product.id}/analytics" ],
      [ "GET my/analytics?shop_id", :get, "/api/v1/my/analytics?shop_id=#{s}" ],
      [ "POST relaunch_expired shop_id", :post, "/api/v1/my/listings/relaunch_expired", { shop_id: s } ],
      [ "PATCH selling_as shop", :patch, "/api/v1/users/me/selling_as", { shop_id: s } ]
    ]
  end

  Authz116::ACTORS.each do |actor|
    it "#{actor}: every member-only 1.1.6 endpoint of shop A is refused, and nothing changes" do
      aggregate_failures do
        endpoints.each { |label, verb, path, params| attempt(label, verb, path, actor, params: params || {}) }
      end
      expect(shop.reload.attributes.slice("name", "status", "owner_id")).to eq("name" => shop.name, "status" => "active", "owner_id" => owner.id)
      expect(shop.shop_members.pluck(:user_id, :role).to_h).to eq(owner.id => "owner", manager.id => "manager", staff.id => "staff")
      expect(invite.reload).to be_pending
      expect(request_.reload).to be_requested
      expect(product.reload.attributes.slice("shop_id", "user_id")).to eq("shop_id" => shop.id, "user_id" => staff.id)
      expect(product.expires_at).to be < Time.current
      expect(others_listing.reload.shop_id).to be_nil
      expect(public_send(actor).reload.active_shop_id).to be_nil unless actor == :guest
      expect(VerificationRequest.where(subject: shop).count).to eq(1)
    end
  end

  # The shop chat: its buyer and the team, no one else.
  (Authz116::ACTORS - [ :buyer ]).each do |actor|
    it "#{actor}: the buyer↔shop chat is closed to them (read, messages, write)" do
      aggregate_failures do
        attempt("GET shop chat", :get, "/api/v1/conversations/#{shop_chat.id}", actor)
        attempt("GET shop chat messages", :get, "/api/v1/conversations/#{shop_chat.id}/messages", actor)
        attempt("POST shop chat message", :post, "/api/v1/conversations/#{shop_chat.id}/messages", actor, params: { message: { body: "hi" } })
      end
      expect(shop_chat.messages.count).to eq(1)
    end
  end

  it "the buyer CAN read their own chat with the shop (the control case)" do
    get "/api/v1/conversations/#{shop_chat.id}", headers: buyer.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

  describe "public reads leak nothing member-only" do
    it "GET /shops/:id as a stranger: no role, no owner, no private phone" do
      shop.update!(phone_public: false)
      get "/api/v1/shops/#{shop.id}", headers: stranger.create_new_auth_token
      body = response.parsed_body["shop"]
      expect(body["role"]).to be_nil
      expect(body).not_to have_key("owner")
      expect(body["phone"]).to be_nil
    end

    it "GET verification current for shop A as a stranger: refused or no private details" do
      get "/api/v1/verification_requests/current?subject=shop:#{shop.id}", headers: stranger.create_new_auth_token
      if response.successful?
        status = response.parsed_body["verification_status"]
        expect(status["can_apply"]).to be(false)
        expect(status.dig("request", "name_on_document")).to be_nil
        expect(status.dig("request", "document_last4")).to be_nil
      else
        expect([ 403, 404 ]).to include(response.status)
      end
    end

    it "GET /reports and /my/shop_invites list only the caller's own" do
      create(:report, reporter: buyer) if FactoryBot.factories.registered?(:report)
      get "/api/v1/reports", headers: stranger.create_new_auth_token
      expect(response.parsed_body.to_s).not_to include("\"reporter_id\":#{buyer.id}")
      get "/api/v1/my/shop_invites", headers: stranger.create_new_auth_token
      expect(response.parsed_body["shop_invites"] || []).to be_empty
    end

    it "DELETE someone else's block does not lift it" do
      Block.create!(blocker: buyer, blocked: owner) if defined?(Block)
      delete "/api/v1/users/#{owner.id}/block", headers: stranger.create_new_auth_token
      expect(Block.where(blocker: buyer, blocked: owner)).to exist if defined?(Block)
    end
  end

  describe "rate limits on the new write endpoints" do
    it "duplicate is capped like create (30 a day per user)" do
      mine = create(:listing, :active, user: stranger)
      statuses = Array.new(31) do
        post "/api/v1/my/listings/#{mine.id}/duplicate", params: { shop_id: nil }, headers: stranger.create_new_auth_token, as: :json
        response.status
      end
      expect(statuses.first(30)).to all(eq(201))
      expect(statuses.last).to eq(429)
    end
  end
end
