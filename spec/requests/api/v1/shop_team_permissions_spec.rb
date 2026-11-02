require "swagger_helper"

# SHOP-3 DoD (API): the permission matrix, one request per cell; remove / leave
# with audit events. hatiwal-mobile/docs/SHOPS.md, "Permission matrix".
RSpec.describe "Shop team permissions", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:outsider) { create(:user) }
  let(:json_type) { { "Content-Type" => "application/json" } }

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user).merge(json_type)

  path "/api/v1/shops/{shop_id}/members" do
    get "the team (every member)" do
      tags "Shops — team"
      description "Owner first, then by join date. Each member: user {id, name, avatar_url}, role, joined_at. " \
                  "Never an email or a phone."
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:shop_id) { shop.id }
      let(:headers) { auth_headers_for(staff) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "200", "the list, read-only for staff" do
        run_test! do
          expect(json["shop_members"].map { |m| [ m["user"]["id"], m["role"] ] }).to eq([ [ owner.id, "owner" ], [ staff.id, "staff" ] ])
          expect(response.body).not_to include(owner.email, staff.email)
        end
      end

      response "403", "not a member" do
        let(:headers) { auth_headers_for(outsider) }

        run_test! { expect(json["code"]).to eq("not_a_member") }
      end
    end
  end

  path "/api/v1/shops/{shop_id}/members/{user_id}" do
    delete "remove a Staff member (owner)" do
      tags "Shops — team"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :user_id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:shop_id) { shop.id }
      let(:user_id) { staff.id }
      let(:headers) { auth_headers_for(owner) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "204", "removed, told and logged" do
        run_test! do
          expect(shop.member?(staff)).to be(false)
          expect(ShopAuditEvent.where(shop: shop, action: "removed", actor: owner, target_user: staff)).to exist
        end
      end
    end
  end

  path "/api/v1/shops/{shop_id}/membership" do
    delete "leave the shop (staff)" do
      tags "Shops — team"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:shop_id) { shop.id }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "204", "left" do
        let(:headers) { auth_headers_for(staff) }

        run_test! { expect(ShopAuditEvent.where(shop: shop, action: "left", target_user: staff)).to exist }
      end

      response "422", "the owner can't leave" do
        let(:headers) { auth_headers_for(owner) }

        run_test! { expect(json["code"]).to eq("owner_cannot_leave") }
      end
    end
  end

  it "removing someone drops them back to Me at once and pushes them" do
    staff.update!(active_shop: shop)
    expect { delete "/api/v1/shops/#{shop.id}/members/#{staff.id}", headers: h(owner) }
      .to have_enqueued_job(ShopTeamPushJob).with("shop_membership_changed", staff.id, shop.id, owner.id, "removed")
    expect(staff.reload.active_shop_id).to be_nil
  end

  it "the owner can't be removed; staff can't remove anyone" do
    delete "/api/v1/shops/#{shop.id}/members/#{owner.id}", headers: h(owner)
    expect(json["code"]).to eq("owner_cannot_leave")
    other = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    delete "/api/v1/shops/#{shop.id}/members/#{other.id}", headers: h(staff)
    expect([ response.status, json["code"] ]).to eq([ 403, "forbidden" ])
  end

  it "an outsider can't leave a shop they aren't in" do
    delete "/api/v1/shops/#{shop.id}/membership", headers: h(outsider)
    expect([ response.status, json["code"] ]).to eq([ 403, "not_a_member" ])
  end

  describe "the matrix" do
    it "Selling as the shop: owner and staff yes, an outsider no" do
      [ owner, staff ].each do |u|
        patch "/api/v1/users/me/selling_as", params: { shop_id: shop.id }.to_json, headers: h(u)
        expect(response).to have_http_status(:ok), u == owner ? "owner" : "staff"
      end
      patch "/api/v1/users/me/selling_as", params: { shop_id: shop.id }.to_json, headers: h(outsider)
      expect(response).not_to have_http_status(:ok)
    end

    it "edit shop info and close the shop: owner only" do
      patch "/api/v1/shops/#{shop.id}", params: { shop: { description: "New" } }.to_json, headers: h(staff)
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/shops/#{shop.id}", headers: h(staff)
      expect(response).to have_http_status(:forbidden)
      patch "/api/v1/shops/#{shop.id}", params: { shop: { description: "New" } }.to_json, headers: h(owner)
      expect(response).to have_http_status(:ok)
    end

    it "the verification card: every member reads it; only the owner applies" do
      get "/api/v1/verification_requests/current", params: { subject: "shop:#{shop.id}" }, headers: auth_headers_for(staff)
      expect(response).to have_http_status(:ok)
      get "/api/v1/verification_requests/current", params: { subject: "shop:#{shop.id}" }, headers: auth_headers_for(outsider)
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/verification_requests", params: { subject: "shop:#{shop.id}", verification_request: { document_type: "e_tazkira" } },
                                            headers: auth_headers_for(staff)
      expect(response).to have_http_status(:forbidden)
    end

    it "invite and cancel: owner only" do
      post "/api/v1/shops/#{shop.id}/invites", params: {}.to_json, headers: h(staff)
      expect(json["code"]).to eq("forbidden")
      invite = create(:shop_invite, shop: shop)
      delete "/api/v1/shops/#{shop.id}/invites/#{invite.id}", headers: h(staff)
      expect(json["code"]).to eq("forbidden")
      get "/api/v1/shops/#{shop.id}/invites", headers: h(staff)
      expect(response).to have_http_status(:forbidden)
    end

    it "Message shop as a buyer: hidden for members (own_shop), open to everyone else" do
      post "/api/v1/shops/#{shop.id}/conversations", params: {}.to_json, headers: h(staff)
      expect(json["code"]).to eq("own_shop")
      post "/api/v1/shops/#{shop.id}/conversations", params: {}.to_json, headers: h(outsider)
      expect(response).to have_http_status(:created)
    end

    it "closing the shop cancels pending invites and tells every staff member" do
      invite = create(:shop_invite, shop: shop)
      staff
      expect { shop.close! }.to have_enqueued_job(ShopTeamPushJob).with("shop_membership_changed", staff.id, shop.id, nil, "closed")
      expect(invite.reload).to be_cancelled
      expect(shop.member?(staff)).to be(false)
    end

    it "the admin's Remove member is audited too" do
      staff
      expect(shop.remove_member!(shop.shop_members.find_by(user: staff))).to be(true)
      expect(ShopAuditEvent.find_by(shop: shop, action: "removed")).to have_attributes(actor_id: nil, target_user_id: staff.id)
    end
  end
end
