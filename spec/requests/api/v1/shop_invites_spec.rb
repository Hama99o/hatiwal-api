require "swagger_helper"

# SHOP-3 DoD (API): invites — create (link / email; no phone), list, cancel,
# resend; 7-day expiry; single use; 20 a day per shop; team_full.
# hatiwal-mobile/docs/SHOPS.md, "Phase 3 — the team".
RSpec.describe "Shop invites", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:headers) { auth_headers_for(owner) }

  def json = JSON.parse(response.body)

  path "/api/v1/shops/{shop_id}/invites" do
    parameter name: :shop_id, in: :path, type: :integer
    parameter name: :"access-token", in: :header, type: :string, required: true
    parameter name: :client,         in: :header, type: :string, required: true
    parameter name: :uid,            in: :header, type: :string, required: true
    let(:shop_id) { shop.id }
    let(:"access-token") { headers["access-token"] }
    let(:client) { headers["client"] }
    let(:uid) { headers["uid"] }

    post "invite someone as Staff (owner)" do
      tags "Shops — team"
      description "No email = a plain link (the main path, shared on WhatsApp). An email invite binds to that " \
                  "CONFIRMED email. No phone (phones are not verified). Refused: cannot_invite_self, already_member, " \
                  "team_full, shop_unavailable (422); forbidden / not_a_member (403); too_many_invites (429, 20 a day per shop)."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :body, in: :body, schema: { type: :object, properties: { email: { type: :string } } }

      response "201", "a link invite" do
        let(:body) { {} }

        run_test! do
          invite = json["shop_invite"]
          expect(invite).to include("status" => "pending", "email" => nil, "role" => "staff")
          expect(invite["url"]).to end_with("/join/#{ShopInvite.last.token}")
          expect(Time.zone.parse(invite["expires_at"])).to be_within(1.minute).of(7.days.from_now)
        end
      end

      response "403", "staff can't invite" do
        let(:headers) do
          staff = create(:user)
          shop.shop_members.create!(user: staff, role: :staff)
          auth_headers_for(staff)
        end
        let(:body) { {} }

        run_test! { expect(json["code"]).to eq("forbidden") }
      end
    end

    get "the owner's invites, pending first" do
      tags "Shops — team"
      produces "application/json"
      security [ { bearer: [] } ]

      response "200", "invites" do
        before do
          create(:shop_invite, shop: shop).cancel!(owner)
          create(:shop_invite, shop: shop, email: "ali@example.com")
        end

        run_test! do
          expect(json["shop_invites"].pluck("status")).to eq(%w[pending cancelled])
          expect(json["shop_invites"].first.keys).to include("url", "email", "expires_at")
        end
      end
    end
  end

  path "/api/v1/shops/{shop_id}/invites/{id}" do
    delete "cancel an invite (owner)" do
      tags "Shops — team"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:shop_id) { shop.id }
      let(:id) { create(:shop_invite, shop: shop).id }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "200", "cancelled (logged)" do
        run_test! { expect(json["shop_invite"]["status"]).to eq("cancelled") }
      end
    end
  end

  path "/api/v1/shops/{shop_id}/invites/{id}/resend" do
    post "push an email invite again (owner)" do
      tags "Shops — team"
      description "Email invites only (a link is shared again by the app). Pushes the invited account if it exists " \
                  "and its email is confirmed. 410 when the invite is no longer pending."
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:shop_id) { shop.id }
      let(:id) { create(:shop_invite, shop: shop, email: "ali@example.com").id }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "200", "sent again" do
        run_test! { expect(json["shop_invite"]["status"]).to eq("pending") }
      end
    end
  end

  def invite(params = {}, as: headers)
    post "/api/v1/shops/#{shop.id}/invites", params: params.to_json, headers: as.merge("Content-Type" => "application/json")
  end

  it "an email invite is stored lower-cased; a phone is not a thing" do
    invite({ email: " Ali@Example.COM " })
    expect(json["shop_invite"]["email"]).to eq("ali@example.com")
    invite({ phone: "+93700000000" })
    expect(response).to have_http_status(:created)
    expect(ShopInvite.last.attributes).not_to have_key("phone")
  end

  it "refuses yourself and someone already in the team" do
    invite({ email: owner.email.upcase })
    expect(json["code"]).to eq("cannot_invite_self")
    staff = create(:user)
    shop.shop_members.create!(user: staff, role: :staff)
    invite({ email: staff.email })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["code"]).to eq("already_member")
  end

  it "refuses when the team is full (20 people)" do
    (Shop::TEAM_LIMIT - 1).times { shop.shop_members.create!(user: create(:user), role: :staff) }
    invite
    expect(json["code"]).to eq("team_full")
  end

  it "allows 20 invites a day per shop, then 429 too_many_invites" do
    create_list(:shop_invite, ShopInvite::DAILY_LIMIT, shop: shop)
    invite
    expect(response).to have_http_status(:too_many_requests)
    expect(json["code"]).to eq("too_many_invites")
    travel_to(25.hours.from_now) do
      invite(as: auth_headers_for(owner))
      expect(response).to have_http_status(:created)
    end
  end

  it "refuses a shop that isn't open" do
    shop.suspended!
    invite
    expect(json["code"]).to eq("shop_unavailable")
  end

  it "pushes an existing CONFIRMED account invited by email, never an unconfirmed one" do
    confirmed = create(:user, confirmed_at: Time.current)
    unconfirmed = create(:user, confirmed_at: nil)
    expect { invite({ email: confirmed.email }) }.to have_enqueued_job(ShopTeamPushJob).with("shop_invite", confirmed.id, shop.id, owner.id, nil, kind_of(Integer))
    expect { invite({ email: unconfirmed.email }) }.not_to have_enqueued_job(ShopTeamPushJob)
  end

  it "the owner cancels (audit-logged); resend works for email invites only" do
    link = create(:shop_invite, shop: shop)
    by_email = create(:shop_invite, shop: shop, email: create(:user, confirmed_at: Time.current).email)

    delete "/api/v1/shops/#{shop.id}/invites/#{link.id}", headers: headers
    expect(json["shop_invite"]["status"]).to eq("cancelled")
    expect(ShopAuditEvent.where(shop: shop, action: "invite_cancelled").count).to eq(1)

    post "/api/v1/shops/#{shop.id}/invites/#{link.id}/resend", headers: headers
    expect(response).to have_http_status(:gone)
    expect { post "/api/v1/shops/#{shop.id}/invites/#{by_email.id}/resend", headers: headers }
      .to have_enqueued_job(ShopTeamPushJob)
    expect(response).to have_http_status(:ok)
  end

  it "every invite is audit-logged" do
    invite
    expect(ShopAuditEvent.where(shop: shop, action: "invited", actor: owner)).to exist
  end

  it "an expired invite shows as expired in the owner's list" do
    create(:shop_invite, :expired, shop: shop)
    get "/api/v1/shops/#{shop.id}/invites", headers: headers
    expect(json["shop_invites"].first["status"]).to eq("expired")
  end

  it "the shop_invite push carries the invite token, only for the bound confirmed account" do
    confirmed = create(:user, confirmed_at: Time.current, push_token: "ExponentPushToken[i]")
    invite = create(:shop_invite, shop: shop, email: confirmed.email)
    sent = []
    allow(Notifications::ExpoPushService).to receive(:deliver) { |**kw| sent << kw; Struct.new(:error).new(nil) }

    ShopTeamPushJob.perform_now("shop_invite", confirmed.id, shop.id, owner.id, nil, invite.id)
    expect(sent.last[:data]).to include(type: "shop_invite", shopId: shop.id, token: invite.token)

    other = create(:user, confirmed_at: Time.current, push_token: "ExponentPushToken[o]")
    ShopTeamPushJob.perform_now("shop_invite", other.id, shop.id, owner.id, nil, invite.id)
    expect(sent.last[:data]).not_to have_key(:token)

    invite.cancel!(owner)
    ShopTeamPushJob.perform_now("shop_invite", confirmed.id, shop.id, owner.id, nil, invite.id)
    expect(sent.last[:data]).not_to have_key(:token)
  end
end
