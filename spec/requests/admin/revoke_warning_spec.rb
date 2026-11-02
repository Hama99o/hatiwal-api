require "rails_helper"

# Admin "Revoke" on a warning (owner, 2026-10-19), from the user and shop pages.
RSpec.describe "Admin: revoke a warning", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  before { sign_in admin, scope: :admin_user }

  it "revokes a user's warning, logs it, and the user no longer sees it" do
    user = create(:user)
    warning = user.issue_warning!(admin_user: admin, reason: "Spam")

    get admin_user_path(user)
    expect(response.body).to include("revoke-warning-#{warning.id}")

    patch revoke_admin_user_warning_path(warning), params: { revoke_reason: "Wrong person" }

    expect(response).to redirect_to(admin_user_path(user))
    expect(warning.reload).to be_revoked
    expect(AdminAuditLog.where(action: "revoke_warning", target: user)).to exist

    get "/api/v1/users/warnings", headers: auth_headers_for(user), as: :json
    body = JSON.parse(response.body)
    expect(body["warnings"]).to be_empty
    expect(body["meta"]["active_count"]).to eq(0)
  end

  it "reinstates a user suspended by 3 strikes" do
    user = create(:user)
    warnings = Array.new(3) { user.issue_warning!(admin_user: admin, reason: "Spam") }

    patch revoke_admin_user_warning_path(warnings.first), params: { revoke_reason: "Appeal" }

    expect(user.reload).to be_active
  end

  it "needs a reason" do
    warning = create(:user_warning)

    patch revoke_admin_user_warning_path(warning), params: { revoke_reason: " " }

    expect(response).to redirect_to(admin_user_path(warning.user))
    expect(flash[:alert]).to include("Write why")
    expect(warning.reload).not_to be_revoked
  end

  it "revokes a shop's warning from the shop page and says a suspended shop stays suspended" do
    shop = create(:shop)
    warnings = Array.new(3) { shop.issue_warning!(admin_user: admin, reason: "Prohibited") }

    get admin_shop_path(shop)
    expect(response.body).to include("shop-warnings", "revoke-warning-#{warnings.first.id}")

    patch revoke_admin_user_warning_path(warnings.first), params: { revoke_reason: "Mistake" }

    expect(response).to redirect_to(admin_shop_path(shop))
    expect(flash[:notice]).to include("still suspended")
    expect(shop.active_warnings_count).to eq(2)
    expect(AdminAuditLog.where(action: "revoke_warning", target: shop)).to exist
  end

  it "revokes from the warning's own page and comes back to it" do
    warning = create(:user_warning)

    get admin_user_warning_path(warning)
    expect(response.body).to include("revoke-warning-#{warning.id}", "Revoke warning", "Revoked by", "Issued by")

    patch revoke_admin_user_warning_path(warning, from: "warning"), params: { revoke_reason: "Mistake" }

    expect(response).to redirect_to(admin_user_warning_path(warning))
    expect(warning.reload).to be_revoked
    follow_redirect!
    expect(response.body).to include("Revoked", "Mistake")
    expect(response.body).not_to include("revoke-warning-#{warning.id}")
  end

  it "requires an admin" do
    sign_out :admin_user
    warning = create(:user_warning)

    patch revoke_admin_user_warning_path(warning), params: { revoke_reason: "x" }

    expect(warning.reload).not_to be_revoked
  end
end
