require "rails_helper"

RSpec.describe "Unsubscribe from bulk email (public, no login)", type: :request do
  let(:user)  { create(:user, preferred_language: "ps") }
  let(:token) { user.signed_id(purpose: User::UNSUBSCRIBE_PURPOSE) }

  it "shows the page in the user's language, RTL, without logging in" do
    get unsubscribe_path(token: token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('dir="rtl"').and include(I18n.t("unsubscribe.confirm", locale: :ps))
  end

  # RFC 8058 one-click: a mail client POSTs with no CSRF token.
  it "opts out on a one-click POST without a CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    post unsubscribe_path(token: token), params: "List-Unsubscribe=One-Click"

    expect(response).to have_http_status(:ok)
    expect(user.reload.email_opt_out_at).to be_present
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "offers an undo, so a forwarded email can't opt someone out for good" do
    post unsubscribe_path(token: token)
    expect(response.body).to include('id="undo"')

    post undo_unsubscribe_path(token: token)

    expect(user.reload.email_opt_out_at).to be_nil
    expect(response.body).to include(I18n.t("unsubscribe.undone", locale: :ps))
  end

  it "rejects a bad or test token without touching anyone" do
    get unsubscribe_path(token: "test-copy")

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('id="invalid-link"')
  end
end
