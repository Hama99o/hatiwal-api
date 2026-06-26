# frozen_string_literal: true

require "signet/oauth_2/client"

# Google OAuth2 service — matches MultiMagic's GoogleConnect.
#
# Used by Admin::GoogleAuthController for the server-side authorization-code flow:
#   1. client.authorization_uri  → redirect admin to Google
#   2. client.code = params[:code]; client.fetch_access_token!  → exchange code
#   3. Faraday.get(userinfo, access_token)  → get email
#
# Credentials are stored encrypted in config/credentials.yml.enc:
#   google_client_id:     ...
#   google_client_secret: ...
class GoogleConnect
  class << self
    def client(opt = {})
      Signet::OAuth2::Client.new(client_options.merge(opt))
    end

    def client_options
      {
        client_id:              Rails.application.credentials[:google_client_id],
        client_secret:          Rails.application.credentials[:google_client_secret],
        authorization_uri:      "https://accounts.google.com/o/oauth2/auth",
        token_credential_uri:   "https://accounts.google.com/o/oauth2/token",
        scope:                  "email profile openid",
        redirect_uri:           callback_url
      }
    end

    private

    def callback_url
      base = ENV.fetch("APP_DOMAIN", "http://localhost:3000")
                .sub(%r{\Ahttps?://}, "")
      host = base.split(":").first
      port = base.include?(":") ? ":#{base.split(':').last}" : ""
      protocol = ENV.fetch("APP_DOMAIN", "http://localhost:3000").start_with?("https") ? "https" : "http"
      "#{protocol}://#{host}#{port}/admin/auth/google/callback"
    end
  end
end
