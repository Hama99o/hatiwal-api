# frozen_string_literal: true

# Admin Google OAuth — server-side authorization-code flow via GoogleConnect/Signet.
# Matches MultiMagic's OauthServicesController pattern.
#
# Flow:
#   GET  /admin/auth/google           → initiate: redirect to Google consent screen
#   GET  /admin/auth/google/callback  → callback: exchange code, fetch user info, sign in
#
# Security: only existing AdminUser records may sign in — no auto-creation.
# A random `state` param is round-tripped through the session to prevent CSRF.
module Admin
  class GoogleAuthController < ActionController::Base
    include Devise::Controllers::Helpers

    protect_from_forgery with: :exception

    GOOGLE_USERINFO_URI = "https://www.googleapis.com/oauth2/v2/userinfo"

    # GET /admin/auth/google
    def initiate
      return deny("Google sign-in is not configured.") if google_client_id.blank?

      state = SecureRandom.hex(16)
      session[:google_oauth_state] = state

      client = GoogleConnect.client(state: state)
      redirect_to client.authorization_uri.to_s, allow_other_host: true
    end

    # GET /admin/auth/google/callback
    def callback
      return deny("Google sign-in was cancelled.") if params[:error].present?
      return deny("Invalid OAuth state. Please try again.") if params[:state] != session.delete(:google_oauth_state)

      user_info = exchange_and_fetch(params[:code])
      return deny("Could not complete Google sign-in. Please try again.") unless user_info

      email = user_info[:email]&.strip&.downcase
      admin = AdminUser.find_by(email: email)
      return deny("#{email} is not authorized to access the admin panel.") unless admin

      sign_in(:admin_user, admin)
      redirect_to admin_root_path, notice: "Signed in as #{admin.name} via Google."
    end

    private

    def exchange_and_fetch(code)
      client = GoogleConnect.client
      client.code = code
      client.fetch_access_token!

      response = Faraday.get(GOOGLE_USERINFO_URI, {}, { "Authorization" => "Bearer #{client.access_token}" })
      return nil unless response.status == 200

      JSON.parse(response.body).symbolize_keys
    rescue StandardError => e
      Rails.logger.error("Admin Google OAuth error: #{e.message}")
      nil
    end

    def google_client_id
      Rails.application.credentials[:google_client_id]
    end

    def deny(message)
      redirect_to new_admin_user_session_path, alert: message
    end
  end
end
