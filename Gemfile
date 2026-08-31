source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "image_processing", "~> 1.2"

# Auth
gem "devise_token_auth"
gem "devise"

# Authorization
gem "pundit"

# Admin dashboard (server-rendered web, separate from the JSON API)
gem "administrate"
gem "propshaft"
gem "chartkick"
gem "groupdate"

# Serialization
gem "blueprinter"

# Pagination
gem "pagy", "~> 43.6"

# CORS
gem "rack-cors"

# HTTP client (used for Google ID token verification)
gem "faraday"

# Google OAuth2 server-side code flow (admin login)
gem "signet"

# Email delivery
gem "postmark-rails"

# Active Storage
gem "aws-sdk-s3", require: false

# Solid adapters (cache, queue, cable)
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "redis", "~> 5.0"

# Swagger API docs served at /api-docs (admin-gated in routes). Available in all
# environments so production can serve them; rswag-specs (below) stays in test
# for regenerating swagger.yaml from the request specs.
gem "rswag-api"
gem "rswag-ui"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "bundler-audit", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rswag-specs"

  # Guard
  gem "guard"
  gem "guard-rspec", require: false
  gem "guard-rubocop", require: false
end

group :test do
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "webmock"
  gem "simplecov", require: false
end
