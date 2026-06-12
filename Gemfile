source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "image_processing", "~> 2.0"

# Auth
gem "devise_token_auth"
gem "devise"

# Authorization
gem "pundit"

# Serialization
gem "blueprinter"

# Pagination
gem "pagy", "~> 8.0"

# CORS
gem "rack-cors"

# Active Storage
gem "aws-sdk-s3", require: false

# Solid adapters (cache, queue, cable)
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "bundler-audit", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rswag"

  # Guard
  gem "guard"
  gem "guard-rspec", require: false
  gem "guard-rubocop", require: false
end

group :test do
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "simplecov", require: false
end
