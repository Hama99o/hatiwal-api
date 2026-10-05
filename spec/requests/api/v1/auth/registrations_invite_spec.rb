require "rails_helper"

# SHOP-3 DoD (API): sign-up with `invite_token` keeps the invite; an email
# invite matches only a CONFIRMED email; accept is still needed.
RSpec.describe "Sign-up from a shop invite", type: :request do
  let(:shop) { create(:shop, name: "Safi Cosmetics") }

  def sign_up(email, **extra)
    post "/api/v1/auth", params: { email: email, password: "Password123!", password_confirmation: "Password123!",
                                   firstname: "Ali", lastname: "Ahmadi" }.merge(extra), as: :json
  end

  it "returns the invite card with the new account; nobody joins until accept" do
    invite = create(:shop_invite, shop: shop)
    sign_up("ali@example.com", invite_token: invite.token)
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["shop_invite"]).to include("status" => "pending")
    expect(body["shop_invite"]["shop"]).to include("name" => "Safi Cosmetics")
    user = User.find_by(email: "ali@example.com")
    expect(shop.member?(user)).to be(false)
    expect(invite.reload).to be_pending

    post "/api/v1/shop_invites/#{invite.token}/accept", headers: auth_headers_for(user.tap { |u| u.password = "Password123!" })
    expect(response).to have_http_status(:ok)
    expect(shop.member?(user)).to be(true)
  end

  it "an unknown or missing token changes nothing about sign-up" do
    sign_up("nobody@example.com", invite_token: "not-a-token")
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).not_to have_key("shop_invite")
    sign_up("plain@example.com")
    expect(JSON.parse(response.body)).not_to have_key("shop_invite")
  end

  it "an email invite waits for that email to be CONFIRMED before it can be accepted" do
    invite = create(:shop_invite, shop: shop, email: "zahra@example.com")
    sign_up("zahra@example.com", invite_token: invite.token)
    zahra = User.find_by(email: "zahra@example.com")
    zahra.password = "Password123!"
    expect(zahra.confirmed_at).to be_nil

    post "/api/v1/shop_invites/#{invite.token}/accept", headers: auth_headers_for(zahra)
    expect(JSON.parse(response.body)["code"]).to eq("invite_wrong_account")

    zahra.update_column(:confirmed_at, Time.current)
    post "/api/v1/shop_invites/#{invite.token}/accept", headers: auth_headers_for(zahra)
    expect(response).to have_http_status(:ok)
  end
end
