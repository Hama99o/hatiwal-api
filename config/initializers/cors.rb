# CORS fails CLOSED in production: the response exposes rotating auth-token
# headers, so a wildcard default would let any web origin read them. Set
# ALLOWED_ORIGINS (comma-separated) in .env.production. Native mobile apps are
# unaffected (CORS is a browser mechanism) and the Next.js web client talks to
# Rails via its own same-origin proxy — so an empty production list breaks
# nothing until a browser client legitimately needs direct access.
allowed_origins = ENV.fetch("ALLOWED_ORIGINS", Rails.env.production? ? "" : "*")
                     .split(",").map(&:strip).compact_blank

if allowed_origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*allowed_origins)

      resource "*",
        headers: :any,
        expose: [ "access-token", "expiry", "token-type", "uid", "client" ],
        methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
    end
  end
end
