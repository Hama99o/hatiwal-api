require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HatiwalApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # DeviseTokenAuth / Devise (via `authenticate_user!`) reference the session,
    # which API-only mode strips out — causing
    # `ActionDispatch::Request::Session::DisabledSessionError` on protected
    # endpoints. Add the session middleware back so token auth works.
    config.session_store :cookie_store, key: "_hatiwal_api_session"
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    # The server-rendered admin dashboard (Administrate, mounted at /admin) needs
    # flash messages on top of the cookies/session middleware added above. The
    # JSON API never uses flash, so this only affects the admin web views.
    config.middleware.use ActionDispatch::Flash

    # Administrate's edit/update/destroy and the logout button submit HTML forms
    # that tunnel PATCH/PUT/DELETE through POST + a `_method` param. API-only
    # mode omits Rack::MethodOverride, so those verbs never reach the router —
    # add it back. The JSON API uses real HTTP verbs and is unaffected.
    config.middleware.use Rack::MethodOverride

    # Devise inserts Warden::Manager early in the (api-only) stack — ahead of the
    # session middleware we re-added above. Normal requests survive this because
    # the session is populated by the time a controller calls `set_user`, but
    # Warden's test `login_as` sets the user on the way in, before the session
    # exists, breaking :timeoutable. Move Warden after the session + flash so it
    # always has a session to read.
    config.middleware.move_after ActionDispatch::Flash, Warden::Manager

    # Gmail SMTP — credentials stored in config/credentials.yml.enc.
    # Matches MultiMagic's email setup. Environment files can override
    # delivery_method (e.g. test.rb uses :test); the smtp_settings are
    # inherited everywhere so they only need to be defined once.
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address:              Rails.application.credentials[:smtp_address],
      port:                 Rails.application.credentials[:smtp_port],
      domain:               Rails.application.credentials[:smtp_domain],
      user_name:            Rails.application.credentials[:smtp_username],
      password:             Rails.application.credentials[:smtp_password],
      authentication:       :plain,
      enable_starttls_auto: true
    }
  end
end
