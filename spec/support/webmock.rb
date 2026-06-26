require "webmock/rspec"

# Allow Faraday requests only to explicitly stub-registered URLs.
# localhost is whitelisted for the Rails test server.
WebMock.disable_net_connect!(allow_localhost: true)
