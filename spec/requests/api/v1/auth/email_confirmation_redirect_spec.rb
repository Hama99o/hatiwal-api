require "rails_helper"

# The confirmation LINK, not the confirmation itself.
#
# DeviseTokenAuth redirects to `default_confirm_success_url` with a bare
# `redirect_to`, and since Rails 7 a cross-host redirect raises
# ActionController::Redirecting::OpenRedirectError. So every user who clicked the
# link in their confirmation email got a 500 — while `confirmed_at` was written and
# the account was actually fine. Confirmed by hand against the dev API: HTTP 500,
# confirmed_at set.
RSpec.describe "Email confirmation redirect", type: :request do
  let(:confirm_url) { DeviseTokenAuth.default_confirm_success_url }

  def confirm!(token)
    get "/api/v1/auth/confirmation", params: { confirmation_token: token }
  end

  # Devise's `generate_confirmation_token!` returns the result of `save`, i.e.
  # `true` — not the token. The raw token is what it wrote to the column
  # (confirmable stores it unhashed), which is also the value that goes into the
  # emailed link.
  def raw_confirmation_token_for(user)
    user.send(:generate_confirmation_token!)
    user.confirmation_token
  end

  it "redirects to the configured success URL instead of raising" do
    user = create(:user, confirmed_at: nil)
    raw = raw_confirmation_token_for(user)

    confirm!(raw)

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to start_with(confirm_url)
    expect(user.reload.confirmed_at).to be_present
  end

  it "still confirms the account" do
    user = create(:user, confirmed_at: nil)
    raw = raw_confirmation_token_for(user)

    expect { confirm!(raw) }.to change { user.reload.confirmed_at }.from(nil)
  end

  # The narrow allowance is the point: only the CONFIGURED host may be redirected
  # to. A `redirect_url` in the query is exactly what Rails' open-redirect
  # protection exists to stop, and overriding redirect_to must not reopen it.
  it "does not follow an attacker-supplied redirect_url to another host" do
    user = create(:user, confirmed_at: nil)
    raw = raw_confirmation_token_for(user)

    get "/api/v1/auth/confirmation",
        params: { confirmation_token: raw, redirect_url: "https://evil.example.com/steal" }

    expect(response.headers["Location"].to_s).not_to include("evil.example.com")
  end

  it "rejects an invalid token without redirecting to the success page" do
    confirm!("not-a-real-token")

    expect(response.headers["Location"].to_s).not_to include("account_confirmation_success=true")
  end
end
