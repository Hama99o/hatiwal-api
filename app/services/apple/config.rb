# Sign in with Apple — configuration (docs/APPLE_SIGN_IN.md).
#
# VERIFYING a sign-in needs no secret: Apple's public keys are fetched, and the
# token's audience must be one of our app ids (`bundle_ids`).
# REVOKING an account's Apple authorization on deletion (and exchanging the
# authorization code for the refresh token that revocation needs) needs the
# owner's Sign-in-with-Apple key: team id, key id, the .p8 private key, and the
# client id (the iOS bundle id). Read from credentials `apple:` or ENV
# (APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY / APPLE_CLIENT_ID); when any
# is missing, those calls are logged no-ops and sign-in still works.
module Apple
  module Config
    # The app's bundle id (app.json ios.bundleIdentifier) — public, not a secret.
    DEFAULT_BUNDLE_IDS = %w[com.hatiwal.app].freeze
    KEYS = %i[team_id key_id private_key client_id].freeze

    module_function

    def settings
      creds = Rails.application.credentials.apple || {}
      KEYS.index_with { |k| creds[k].presence || ENV["APPLE_#{k.upcase}"].presence }.compact
    end

    # Accepted `aud` values of an identity token.
    def bundle_ids
      configured = Rails.application.credentials.dig(:apple, :bundle_ids).presence ||
                   ENV["APPLE_BUNDLE_IDS"].to_s.split(",").map(&:strip).presence
      Array(configured || DEFAULT_BUNDLE_IDS)
    end

    def key_configured?
      settings.values_at(*KEYS).all?(&:present?)
    end

    def warn_unconfigured(what)
      Rails.logger.warn("[apple] Sign in with Apple key not configured: #{what} skipped (docs/APPLE_SIGN_IN.md)")
    end
  end
end
