require "swagger_helper"

# "My invitations" (owner, 2026-10-06, 1.1.6): an invited person sees their
# pending invitations in the app, so a missed push never loses one.
RSpec.describe "My shop invitations", type: :request do
  let(:shop) { create(:shop, name: "Kabul Invite Shop") }
  let(:me) { create(:user, :confirmed, email: "invited@hatiwal.test") }
  let!(:invite) { create(:shop_invite, shop: shop, email: "Invited@Hatiwal.test") }

  def json = JSON.parse(response.body)
  def mine(user = me) = (get("/api/v1/my/shop_invites", headers: auth_headers_for(user)) && json["shop_invites"])

  path "/api/v1/my/shop_invites" do
    get "my pending invitations" do
      tags "Shops — team"
      description "Pending, unexpired EMAIL invitations addressed to the caller's CONFIRMED email, for open shops " \
                  "they are not in yet. An unconfirmed email sees none; link invites never show (no addressee). " \
                  "Answer with POST /shop_invites/{token}/accept or /decline. me.pending_shop_invites_count is the badge."
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :page, in: :query, type: :integer, required: false
      let(:headers) { auth_headers_for(me) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "200", "the invitations" do
        run_test! do
          row = json["shop_invites"].sole
          expect(row).to include("id" => invite.id, "token" => invite.token, "role" => "staff",
                                 "inviter_name" => shop.owner.full_name, "expires_at" => invite.expires_at.iso8601)
          expect(row["shop"]).to include("id" => shop.id, "name" => "Kabul Invite Shop", "verified" => false)
          expect(row["shop"]).to have_key("logo_url")
          expect(row).not_to have_key("email")
        end
      end

      response "401", "signed out" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid) { nil }

        run_test!
      end
    end
  end

  it "an unconfirmed email sees none (anyone can type any address at sign-up)" do
    unconfirmed = create(:user, email: "invited2@hatiwal.test")
    create(:shop_invite, shop: shop, email: "invited2@hatiwal.test")
    expect(mine(unconfirmed)).to eq([])
    get "/api/v1/users/me", headers: auth_headers_for(unconfirmed)
    expect(json["user"]).to include("pending_shop_invites_count" => 0)
  end

  it "appears once the email is confirmed (sign up first, confirm later)" do
    newbie = create(:user, email: "later@hatiwal.test")
    later = create(:shop_invite, shop: shop, email: "later@hatiwal.test")
    expect(mine(newbie)).to eq([])
    newbie.update!(confirmed_at: Time.current)
    expect(mine(newbie).map { |r| r["id"] }).to eq([ later.id ])
  end

  it "never shows an expired, cancelled, used or declined one, a link, another person's, or a suspended shop's" do
    create(:shop_invite, :expired, shop: shop, email: me.email)
    create(:shop_invite, shop: shop, email: me.email).update_columns(status: ShopInvite.statuses[:cancelled])
    create(:shop_invite, shop: shop, email: me.email).update_columns(status: ShopInvite.statuses[:declined])
    create(:shop_invite, shop: shop) # a link: no addressee
    create(:shop_invite, shop: shop, email: "someone.else@hatiwal.test")
    create(:shop_invite, shop: create(:shop, :suspended), email: me.email)
    expect(mine.map { |r| r["id"] }).to eq([ invite.id ])
  end

  it "a shop they already work in is not listed" do
    shop.shop_members.create!(user: me, role: :staff)
    expect(mine).to eq([])
  end

  it "accepting by token removes it, and the badge counts it" do
    get "/api/v1/users/me", headers: auth_headers_for(me)
    expect(json["user"]).to include("pending_shop_invites_count" => 1)

    post "/api/v1/shop_invites/#{invite.token}/accept", headers: auth_headers_for(me)
    expect(response).to have_http_status(:ok)
    expect(mine).to eq([])
    get "/api/v1/users/me", headers: auth_headers_for(me)
    expect(json["user"]).to include("pending_shop_invites_count" => 0)
  end

  it "declining by token removes it" do
    post "/api/v1/shop_invites/#{invite.token}/decline", headers: auth_headers_for(me)
    expect(response).to have_http_status(:no_content)
    expect(mine).to eq([])
  end
end
