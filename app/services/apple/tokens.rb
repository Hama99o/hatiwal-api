# Apple's token endpoints, used only so a deleted account's Apple authorization
# can be revoked (App Store guideline 5.1.1(v)):
#   exchange(code) — the one-time authorization code from sign-in → refresh token
#   revoke(token)  — POST /auth/revoke with that refresh token
# Both authenticate with a short-lived ES256 client secret signed by the owner's
# Sign-in-with-Apple key. Without the key (Apple::Config) both are logged no-ops.
module Apple
  module Tokens
    TOKEN_URL = "https://appleid.apple.com/auth/token".freeze
    REVOKE_URL = "https://appleid.apple.com/auth/revoke".freeze
    AUDIENCE = "https://appleid.apple.com".freeze

    module_function

    # The refresh token, or nil (not configured, or Apple refused the code).
    def exchange(code)
      return nil if code.blank?
      unless Apple::Config.key_configured?
        Apple::Config.warn_unconfigured("authorization-code exchange")
        return nil
      end

      response = post(TOKEN_URL, code: code, grant_type: "authorization_code")
      return JSON.parse(response.body)["refresh_token"].presence if response.status == 200

      Rails.logger.warn("[apple] code exchange refused: HTTP #{response.status} #{response.body.to_s.first(200)}")
      nil
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("[apple] code exchange failed: #{e.class}: #{e.message}")
      nil
    end

    # true when Apple accepted the revocation.
    def revoke(refresh_token)
      return false if refresh_token.blank?
      unless Apple::Config.key_configured?
        Apple::Config.warn_unconfigured("token revocation")
        return false
      end

      response = post(REVOKE_URL, token: refresh_token, token_type_hint: "refresh_token")
      return true if response.status == 200

      Rails.logger.warn("[apple] revoke refused: HTTP #{response.status} #{response.body.to_s.first(200)}")
      false
    rescue Faraday::Error => e
      Rails.logger.warn("[apple] revoke failed: #{e.class}: #{e.message}")
      false
    end

    def client_secret
      s = Apple::Config.settings
      key = OpenSSL::PKey::EC.new(s[:private_key].to_s.gsub("\\n", "\n"))
      now = Time.now.to_i
      JWT.encode({ iss: s[:team_id], iat: now, exp: now + 300, aud: AUDIENCE, sub: s[:client_id] },
                 key, "ES256", { kid: s[:key_id] })
    end

    def post(url, **form)
      Faraday.post(url) do |r|
        r.options.timeout = 15
        r.headers["Content-Type"] = "application/x-www-form-urlencoded"
        r.body = URI.encode_www_form(form.merge(client_id: Apple::Config.settings[:client_id], client_secret: client_secret))
      end
    end
  end
end
