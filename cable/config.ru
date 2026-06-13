# Standalone ActionCable server — runs as a separate Puma process.
# This decouples WebSocket connections from the main API process so
# cable throughput never blocks HTTP request handling.
#
# Start: bundle exec puma -p 3008 cable/config.ru
# Docker: see docker-compose.yml `cable` service

require_relative "../config/environment"
Rails.application.eager_load!

run ActionCable.server
