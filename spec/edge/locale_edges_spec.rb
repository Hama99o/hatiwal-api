require "rails_helper"

# Edge pass 1.1.6 (hatiwal-d0, 2026-10-08) — text the API composes reaches the
# reader in THEIR language. The API does not switch locale per request, so
# anything stored or composed server-side must name its locale.
RSpec.describe "Server-composed text in the reader's language — edge cases", type: :request do
  def json = JSON.parse(response.body)

  describe "an auto-suspension (3 warnings), told to a Dari speaker" do
    let(:user) { create(:user, preferred_language: "fa") }
    let(:headers) { auth_headers_for(user) } # signed in before the suspension

    before do
      headers
      I18n.with_locale(:en) { user.send(:auto_suspend_for_strikes!) } # e.g. from the admin panel
    end

    it "an authenticated request's 403: the reason and the message are in Dari" do
      get "/api/v1/users/me", headers: headers
      expect(response).to have_http_status(:forbidden)
      fa = I18n.t("accounts.auto_suspended_reason", count: User::WARNING_BLOCK_THRESHOLD, locale: :fa)
      expect(json["reason"]).to eq(fa)
      expect(json["message"]).to include(fa)
      expect(json["message"]).to start_with(I18n.t("accounts.blocked.suspended", locale: :fa))
    end

    it "a sign-in's 403: the same" do
      post "/api/v1/auth/sign_in", params: { email: user.email, password: "password123" }
      expect(response).to have_http_status(:forbidden)
      body = response.body
      expect(body).to include(I18n.t("accounts.auto_suspended_reason", count: User::WARNING_BLOCK_THRESHOLD, locale: :fa))
      expect(body).not_to include("Automatically suspended")
    end
  end

  it "an admin's own reason is shown as the admin wrote it" do
    user = create(:user, preferred_language: "ps", status: :banned, auto_blocked: false, block_reason: "Spam listings")
    expect(user.display_block_reason).to eq("Spam listings")
  end
end
