require "swagger_helper"

# SHOP-3 "Later", now in 1.1.6 (owner, 2026-10-06): the Manager role + change
# role, transfer ownership, and "replied by" for the team.
# Matrix: Manager = Staff + edit shop info + invite/cancel/resend + remove STAFF.
# Owner only: change roles, transfer, close, apply for Verified, remove a manager.
RSpec.describe "Shop team roles and ownership", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, firstname: "Umair", lastname: "Ownerkhan") }
  let(:shop) { create(:shop, owner: owner) }
  let(:manager) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :manager) } }
  let(:staff) { create(:user, firstname: "Ali", lastname: "Staffkhan").tap { |u| shop.shop_members.create!(user: u, role: :staff) } }

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user).merge("Content-Type" => "application/json")

  path "/api/v1/shops/{shop_id}/members/{user_id}" do
    patch "change a member's role (owner)" do
      tags "Shops — team"
      description "role: manager | staff. Owner only (403 forbidden). The owner's own role only changes by a transfer " \
                  "(422 cannot_change_owner); 422 invalid_role; 404 not_a_member. Audit role_changed; push " \
                  "shop_membership_changed {reason: role_changed} to the person."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :user_id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: { type: :object, properties: { role: { type: :string, enum: %w[manager staff] } },
                                                  required: %w[role] }
      let(:shop_id) { shop.id }
      let(:user_id) { staff.id }
      let(:headers) { auth_headers_for(owner) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }
      let(:body) { { role: "manager" } }

      response "200", "the member with the new role" do
        run_test! do
          expect(json["shop_member"]).to include("role" => "manager")
          expect(ShopAuditEvent.find_by(shop: shop, action: "role_changed").data).to include("from" => "staff", "to" => "manager")
        end
      end

      response "403", "not the owner" do
        let(:headers) { auth_headers_for(manager) }

        run_test! { expect(json["code"]).to eq("forbidden") }
      end
    end
  end

  path "/api/v1/shops/{shop_id}/transfer" do
    post "hand the shop to a member (owner)" do
      tags "Shops — team"
      description "The member becomes the owner; the old owner stays as a manager; shop chats move to the new owner " \
                  "(their seller is the owner); a Verified badge is dropped (it vouched for the old owner's e-Tazkira). " \
                  "→ { shop (owner view, the caller's new role), me }. 422: cannot_transfer_to_self, not_a_member, " \
                  "shop_unavailable, verification_pending. 403 forbidden for anyone but the owner."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: { type: :object, properties: { user_id: { type: :integer } }, required: %w[user_id] }
      let(:shop_id) { shop.id }
      let(:headers) { auth_headers_for(owner) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }
      let(:body) { { user_id: manager.id } }

      response "200", "transferred" do
        run_test! do
          expect(json["shop"]).to include("role" => "manager")
          expect(json["me"]["shops"].find { |s| s["id"] == shop.id }).to include("role" => "manager")
          expect(shop.reload.owner_id).to eq(manager.id)
        end
      end

      response "422", "to yourself" do
        let(:body) { { user_id: owner.id } }

        run_test! { expect(json["code"]).to eq("cannot_transfer_to_self") }
      end
    end
  end

  describe "the Manager role" do
    it "invites, edits the shop and removes STAFF; never a manager or the owner" do
      post "/api/v1/shops/#{shop.id}/invites", params: {}.to_json, headers: h(manager)
      expect(response).to have_http_status(:created)
      patch "/api/v1/shops/#{shop.id}", params: { shop: { description: "Edited by the manager" } }.to_json, headers: h(manager)
      expect(response).to have_http_status(:ok)

      delete "/api/v1/shops/#{shop.id}/members/#{staff.id}", headers: h(manager)
      expect(response).to have_http_status(:no_content)

      other_manager = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :manager) }
      delete "/api/v1/shops/#{shop.id}/members/#{other_manager.id}", headers: h(manager)
      expect([ response.status, json["code"] ]).to eq([ 403, "forbidden" ])
      delete "/api/v1/shops/#{shop.id}/members/#{owner.id}", headers: h(manager)
      expect(json["code"]).to eq("owner_cannot_leave")
    end

    it "can't change roles, transfer, close the shop or apply for Verified" do
      patch "/api/v1/shops/#{shop.id}/members/#{staff.id}", params: { role: "manager" }.to_json, headers: h(manager)
      expect(json["code"]).to eq("forbidden")
      post "/api/v1/shops/#{shop.id}/transfer", params: { user_id: manager.id }.to_json, headers: h(manager)
      expect(json["code"]).to eq("forbidden")
      delete "/api/v1/shops/#{shop.id}", headers: h(manager)
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/verification_requests", params: { subject: "shop:#{shop.id}", verification_request: { document_type: "e_tazkira" } },
                                            headers: auth_headers_for(manager)
      expect(response).to have_http_status(:forbidden)
    end

    it "staff still can't invite or edit" do
      post "/api/v1/shops/#{shop.id}/invites", params: {}.to_json, headers: h(staff)
      expect(json["code"]).to eq("forbidden")
      patch "/api/v1/shops/#{shop.id}", params: { shop: { description: "Nope" } }.to_json, headers: h(staff)
      expect(response).to have_http_status(:forbidden)
    end

    it "the owner may remove a manager; /me says manager" do
      get "/api/v1/users/me", headers: auth_headers_for(manager)
      expect(json["user"]["shops"].find { |s| s["id"] == shop.id }).to include("role" => "manager")
      delete "/api/v1/shops/#{shop.id}/members/#{manager.id}", headers: h(owner)
      expect(response).to have_http_status(:no_content)
    end

    it "change role: the owner's role, a bad role and a stranger are refused; the person is told" do
      patch "/api/v1/shops/#{shop.id}/members/#{owner.id}", params: { role: "staff" }.to_json, headers: h(owner)
      expect(json["code"]).to eq("cannot_change_owner")
      patch "/api/v1/shops/#{shop.id}/members/#{staff.id}", params: { role: "owner" }.to_json, headers: h(owner)
      expect(json["code"]).to eq("invalid_role")
      patch "/api/v1/shops/#{shop.id}/members/#{create(:user).id}", params: { role: "manager" }.to_json, headers: h(owner)
      expect([ response.status, json["code"] ]).to eq([ 404, "not_a_member" ])
      expect do
        patch "/api/v1/shops/#{shop.id}/members/#{staff.id}", params: { role: "manager" }.to_json, headers: h(owner)
      end.to have_enqueued_job(ShopTeamPushJob).with("shop_membership_changed", staff.id, shop.id, owner.id, "role_changed")
    end
  end

  describe "transfer ownership" do
    it "moves the shop, its chats and the sale seller; drops a Verified badge; logs and tells the new owner" do
      buyer = create(:user)
      product = create(:listing, :active, user: owner, shop: shop)
      chat = Conversations::StartService.new(buyer: buyer, listing: product, message_body: "Salaam").call
      shop_chat = Conversations::StartShopService.new(buyer: buyer, shop: shop, message_body: "Hi").call
      shop.update_columns(verified_at: Time.current)

      expect { post "/api/v1/shops/#{shop.id}/transfer", params: { user_id: staff.id }.to_json, headers: h(owner) }
        .to have_enqueued_job(ShopTeamPushJob).with("shop_owner_changed", staff.id, shop.id, owner.id)
      expect(response).to have_http_status(:ok)

      shop.reload
      expect(shop).to have_attributes(owner_id: staff.id, verified_at: nil)
      expect(shop.shop_members.find_by(user: staff).role).to eq("owner")
      expect(shop.shop_members.find_by(user: owner).role).to eq("manager")
      expect([ chat.reload.seller_id, shop_chat.reload.seller_id ]).to eq([ staff.id, staff.id ])
      expect(product.reload.sale_seller_id).to eq(staff.id)
      expect(ShopAuditEvent.find_by(shop: shop, action: "transferred").data).to include("badge_dropped" => true)

      # The old owner, now a manager, may leave; the new owner may not.
      delete "/api/v1/shops/#{shop.id}/membership", headers: h(owner)
      expect(response).to have_http_status(:no_content)
    end

    it "refuses a removed member, a shop under review and a pending Verified request" do
      shop.remove_team_member!(staff, by: owner)
      post "/api/v1/shops/#{shop.id}/transfer", params: { user_id: staff.id }.to_json, headers: h(owner)
      expect(json["code"]).to eq("not_a_member")

      manager
      shop.update_columns(status: Shop.statuses[:pending])
      post "/api/v1/shops/#{shop.id}/transfer", params: { user_id: manager.id }.to_json, headers: h(owner)
      expect(json["code"]).to eq("shop_unavailable")

      shop.update_columns(status: Shop.statuses[:active])
      # A waiting request (eligibility is not this spec's subject).
      VerificationRequest.new(subject: shop, requested_by: owner, status: :requested, document_type: :e_tazkira).save!(validate: false)
      post "/api/v1/shops/#{shop.id}/transfer", params: { user_id: manager.id }.to_json, headers: h(owner)
      expect(json["code"]).to eq("verification_pending")
      expect(shop.reload.owner_id).to eq(owner.id)
    end
  end

  describe "replied by (members only)" do
    let(:buyer) { create(:user) }
    let(:product) { create(:listing, :active, user: owner, shop: shop) }
    let!(:chat) { Conversations::StartService.new(buyer: buyer, listing: product, message_body: "Salaam").call }
    let!(:reply) { chat.messages.create!(user: staff, body: "Yes, we have it", kind: :text) }

    def messages_for(user)
      get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(user)
      json["messages"]
    end

    it "the team sees who replied (their own messages too); the buyer never gets the key" do
      expect(messages_for(owner).find { |m| m["id"] == reply.id }["sent_by"]).to eq("id" => staff.id, "name" => "Ali Staffkhan")
      expect(messages_for(staff).find { |m| m["id"] == reply.id }["sent_by"]).to include("id" => staff.id)
      buyer_rows = messages_for(buyer)
      expect(buyer_rows.map(&:keys).flatten).not_to include("sent_by")
      expect(response.body).not_to include("Staffkhan")
      # The buyer's own message never carries it either, for anyone.
      expect(messages_for(owner).find { |m| m["sender"]["id"] == buyer.id }).not_to have_key("sent_by")
    end

    it "live: the plain stream has no sent_by; the team stream does" do
      expect { BroadcastMessageJob.perform_now(reply.id) }
        .to have_broadcasted_to("conversation_#{chat.id}").with { |d| expect(d[:message]).not_to have_key(:sent_by) }
      expect { BroadcastMessageJob.perform_now(reply.id) }
        .to have_broadcasted_to("conversation_#{chat.id}_team").with { |d| expect(d[:message][:sent_by]).to include(id: staff.id) }
    end
  end
end
