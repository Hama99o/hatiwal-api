require "rails_helper"

# Devise's :confirmable is now on for User, on an app that is already shipped to
# the Play Store and the App Store. It is enabled in its NON-BLOCKING form —
# devise.rb sets allow_unconfirmed_access_for to nil — and these examples exist
# to hold that line. Every one of them is a regression guard against the way
# turning :confirmable on normally breaks a live client:
#
#   * DTA answers signup with NO auth token unless active_for_authentication?
#   * DTA 422s every signup when no confirm_success_url is configured
#   * an unconfirmed user cannot sign in once the grace period lapses
#
# If any example here starts failing, users of the installed app can no longer
# create an account or log in. That is the cost of tightening this.
RSpec.describe "Email confirmation", type: :request do
  include ActiveJob::TestHelper

  def sign_up(email: "newcomer@example.com")
    post "/api/v1/auth",
         params: {
           email:                 email,
           password:              "Password123!",
           password_confirmation: "Password123!",
           firstname:             "New",
           lastname:              "Comer"
         },
         as: :json
  end

  describe "signing up" do
    it "still succeeds without the client sending a confirm_success_url" do
      sign_up

      expect(response).to have_http_status(:ok)
    end

    it "still returns an access token, so the client is logged in as before" do
      sign_up

      expect(response.headers["access-token"]).to be_present
      expect(response.headers["client"]).to be_present
    end

    it "creates the account unconfirmed" do
      sign_up

      expect(User.last.confirmed_at).to be_nil
    end

    it "queues the confirmation email rather than blocking the request on SMTP" do
      expect { sign_up }.to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)
    end
  end

  describe "the confirmation email" do
    # Guards the branded view in app/views/devise/mailer: it rebuilds the
    # confirmation URL by hand, and DTA's ConfirmationsController needs both the
    # token AND the redirect_url to land the user anywhere. Dropping a parameter
    # would leave a link that silently goes nowhere.
    it "carries a link with the confirmation token and the redirect target" do
      perform_enqueued_jobs { sign_up }

      body = ActionMailer::Base.deliveries.last.body.encoded
      expect(body).to include("confirmation_token=")
      expect(body).to include("redirect_url=")
    end
  end

  describe "an unconfirmed user" do
    let!(:user) { create(:user, email: "unconfirmed@example.com") }

    it "has no confirmed_at (the factory does not confirm)" do
      expect(user.confirmed_at).to be_nil
    end

    it "can still sign in — confirmation is a signal, not a gate" do
      post "/api/v1/auth/sign_in",
           params: { email: user.email, password: user.password },
           as:     :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["access-token"]).to be_present
    end

    it "can still reach an authenticated endpoint" do
      get "/api/v1/categories", headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe "following the link in the email" do
    it "stamps confirmed_at" do
      sign_up
      user = User.last
      # Devise stores the confirmation token unhashed, so this is the same value
      # that went into the emailed link — and no redirect_url, exactly as the
      # emailed link arrives. Where that redirect is allowed to land is
      # Api::V1::Auth::ConfirmationsController's job and is covered in
      # email_confirmation_redirect_spec.rb.
      get "/api/v1/auth/confirmation", params: { confirmation_token: user.confirmation_token }

      expect(user.reload.confirmed_at).to be_present
    end
  end
end
