# Verifies an Apple identity token (a JWT Apple signs with RS256) the way Apple
# documents it: the signature against Apple's published keys (JWKS, cached and
# re-fetched once when a token names an unknown key id), iss = Apple, aud = one
# of our bundle ids, not expired, and — against replay — the `nonce` claim equal
# to the SHA-256 (hex) of the raw nonce the app generated and sends us.
#
#   Apple::IdentityToken.verify(token, raw_nonce:) # => claims Hash, or nil
module Apple
  module IdentityToken
    JWKS_URL = "https://appleid.apple.com/auth/keys".freeze
    ISSUER = "https://appleid.apple.com".freeze
    JWKS_CACHE_KEY = "apple/jwks".freeze
    # When a token names an unknown key id, Apple's keys are fetched again at
    # most once per this period: forged tokens (anyone can mint one with any
    # `kid`) must not turn each attempt into a request to Apple (d0 review).
    JWKS_REFETCH_COOLDOWN = 5.minutes
    JWKS_REFETCHED_KEY = "apple/jwks/refetched".freeze

    module_function

    def verify(token, raw_nonce:)
      return nil if token.blank? || raw_nonce.blank?

      claims, = JWT.decode(token, nil, true, algorithms: [ "RS256" ], jwks: method(:jwks),
                                             iss: ISSUER, verify_iss: true,
                                             aud: Apple::Config.bundle_ids, verify_aud: true)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(claims["nonce"].to_s,
                                                                    Digest::SHA256.hexdigest(raw_nonce.to_s))

      claims
    rescue JWT::DecodeError, JSON::ParserError, Faraday::Error => e
      Rails.logger.info("[apple] identity token rejected: #{e.class}: #{e.message}")
      nil
    end

    # JWT's `jwks:` loader. `kid_not_found` means Apple rotated its keys: fetch
    # again once (the cache is otherwise kept for 12 hours).
    def jwks(options = {})
      if options[:kid_not_found]
        # unless_exist: true when THIS call set the marker, i.e. no refetch in
        # the cooldown window; otherwise keep the cached keys (the kid is unknown).
        refetch = Rails.cache.write(JWKS_REFETCHED_KEY, true, expires_in: JWKS_REFETCH_COOLDOWN, unless_exist: true)
        Rails.cache.delete(JWKS_CACHE_KEY) if refetch
      end
      keys = Rails.cache.fetch(JWKS_CACHE_KEY, expires_in: 12.hours) do
        response = Faraday.get(JWKS_URL) { |r| r.options.timeout = 10 }
        raise JWT::DecodeError, "Apple JWKS answered #{response.status}" unless response.status == 200

        JSON.parse(response.body)
      end
      JWT::JWK::Set.new(keys)
    end
  end
end
