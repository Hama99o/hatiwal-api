require "swagger_helper"

# SHOP-3 DoD (API): Join — the public GET shows only the shop card + inviter
# name + status; accept / decline; every error code.
RSpec.describe "Opening a shop invite", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, firstname: "Umair", lastname: "Safi") }
  let(:shop) { create(:shop, owner: owner, name: "Safi Cosmetics") }
  let(:invite) { create(:shop_invite, shop: shop) }
  let(:joiner) { create(:user) }

  def json = JSON.parse(response.body)

  path "/api/v1/shop_invites/{token}" do
    get "the invite, for anyone holding the link (public)" do
      tags "Shops — team"
      description "No login needed (the web join page). Only the shop's card, the inviter's name, the role, the status " \
                  "(pending / accepted / declined / cancelled / expired) and the expiry."
      produces "application/json"
      parameter name: :token, in: :path, type: :string
      let(:token) { invite.token }

      response "200", "the invite card" do
        run_test! do
          expect(json["shop_invite"].keys).to match_array(%w[shop inviter_name role status expires_at])
          expect(json["shop_invite"]).to include("inviter_name" => "Umair Safi", "status" => "pending", "role" => "staff")
          expect(json["shop_invite"]["shop"]).to include("id" => shop.id, "name" => "Safi Cosmetics")
        end
      end

      response "404", "an unknown token" do
        let(:token) { "nope" }

        run_test!
      end
    end
  end

  path "/api/v1/shop_invites/{token}/accept" do
    post "join the shop as Staff" do
      tags "Shops — team"
      description "→ { shop_member, me }. Refused: invite_used / invite_cancelled / invite_expired (410), " \
                  "invite_wrong_account (403), already_member, shop_unavailable, team_full (422)."
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :token, in: :path, type: :string
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:token) { invite.token }
      let(:headers) { auth_headers_for(joiner) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "200", "joined" do
        run_test! do
          expect(json["shop_member"]).to include("role" => "staff")
          expect(json["me"]["shops"].pluck("id")).to include(shop.id)
          expect(invite.reload).to have_attributes(status: "accepted", accepted_by_id: joiner.id)
        end
      end

      response "410", "already used" do
        before { invite.update!(status: :accepted, accepted_by: create(:user)) }

        run_test! { expect(json["code"]).to eq("invite_used") }
      end
    end
  end

  path "/api/v1/shop_invites/{token}/decline" do
    post "say no to the invite" do
      tags "Shops — team"
      description "Logged (declined). The invite can't be used after. Same refusal codes as accept."
      security [ { bearer: [] } ]
      parameter name: :token, in: :path, type: :string
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      let(:token) { invite.token }
      let(:headers) { auth_headers_for(joiner) }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response "204", "declined" do
        run_test! { expect(invite.reload).to be_declined }
      end
    end
  end

  def accept(as: joiner, token: invite.token)
    post "/api/v1/shop_invites/#{token}/accept", headers: auth_headers_for(as)
  end

  it "the public GET reveals no email, no token and no member list, and needs no login" do
    email_invite = create(:shop_invite, shop: shop, email: "secret@example.com")
    get "/api/v1/shop_invites/#{email_invite.token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("secret@example.com", email_invite.token, owner.email)
  end

  it "accept tells the owner and logs it; works once" do
    expect { accept }.to have_enqueued_job(ShopTeamPushJob).with("shop_member_joined", owner.id, shop.id, joiner.id)
    expect(ShopAuditEvent.where(shop: shop, action: "joined", target_user: joiner)).to exist
    accept(as: create(:user))
    expect(response).to have_http_status(:gone)
    expect(json["code"]).to eq("invite_used")
  end

  it "decline is logged, and the invite can't be used after" do
    post "/api/v1/shop_invites/#{invite.token}/decline", headers: auth_headers_for(joiner)
    expect(response).to have_http_status(:no_content)
    expect(invite.reload).to be_declined
    expect(ShopAuditEvent.where(shop: shop, action: "declined")).to exist
    accept
    expect(json["code"]).to eq("invite_used")
  end

  it "answers every refusal with its code" do
    expired = create(:shop_invite, :expired, shop: shop)
    accept(token: expired.token)
    expect([ response.status, json["code"] ]).to eq([ 410, "invite_expired" ])

    cancelled = create(:shop_invite, shop: shop)
    cancelled.cancel!(owner)
    accept(token: cancelled.token)
    expect([ response.status, json["code"] ]).to eq([ 410, "invite_cancelled" ])

    accept(as: owner)
    expect([ response.status, json["code"] ]).to eq([ 422, "already_member" ])

    by_email = create(:shop_invite, shop: shop, email: "ali@example.com")
    accept(token: by_email.token)
    expect([ response.status, json["code"] ]).to eq([ 403, "invite_wrong_account" ])

    closed_shop = create(:shop)
    closed_invite = create(:shop_invite, shop: closed_shop)
    closed_shop.suspended!
    accept(token: closed_invite.token)
    expect([ response.status, json["code"] ]).to eq([ 422, "shop_unavailable" ])

    (Shop::TEAM_LIMIT - 1).times { shop.shop_members.create!(user: create(:user), role: :staff) }
    accept(token: create(:shop_invite, shop: shop).token)
    expect([ response.status, json["code"] ]).to eq([ 422, "team_full" ])
  end

  it "an email invite works only for that CONFIRMED email" do
    ali = create(:user, email: "ali@example.com", confirmed_at: nil)
    by_email = create(:shop_invite, shop: shop, email: "ALI@example.com")
    accept(as: ali, token: by_email.token)
    expect(json["code"]).to eq("invite_wrong_account")
    ali.update_column(:confirmed_at, Time.current)
    accept(as: ali, token: by_email.token)
    expect(response).to have_http_status(:ok)
  end

  it "every code has a sentence in 4 locales" do
    codes = %w[already_member invite_expired invite_used invite_cancelled invite_wrong_account cannot_invite_self
               shop_unavailable owner_cannot_leave not_a_member forbidden team_full too_many_invites]
    User::SUPPORTED_LANGUAGES.each do |locale|
      codes.each { |c| expect(I18n.t("shops.team.errors.#{c}", locale: locale, raise: true)).to be_present }
      %w[shop_invite shop_member_joined shop_membership_changed_removed shop_membership_changed_closed].each do |k|
        expect(I18n.t("push.shop_team.#{k}", locale: locale, shop: "S", name: "A", raise: true)).to include("S")
      end
    end
  end
end
