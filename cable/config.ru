# Standalone ActionCable server — runs as a separate Puma process.
# This decouples WebSocket connections from the main API process so
# cable throughput never blocks HTTP request handling.
#
# Start: bundle exec puma -p 3008 cable/config.ru
# Docker: see docker-compose.yml `cable` service

require_relative "../config/environment"
Rails.application.eager_load!

# Expose a plain-HTTP health-check endpoint at /up so CI readiness polls
# have a reliable 200 target.  ActionCable::Connection::Base#process returns
# 404 for any non-WebSocket GET (websocket.possible? is false), so polling
# the mount path directly would yield 404, not the commonly assumed 426.
# Setting health_check_path causes ActionCable::Server::Base#call to short-
# circuit and return 200 before attempting WebSocket negotiation.
ActionCable.server.config.health_check_path = "/up"

run ActionCable.server
