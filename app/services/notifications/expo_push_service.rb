require "net/http"
require "uri"
require "json"

module Notifications
  # Delivers a single push notification to a device via the Expo Push API.
  #
  #   result = Notifications::ExpoPushService.deliver(
  #     token: "ExponentPushToken[...]", title: "Ahmad", body: "Salaam",
  #     data: { type: "message", conversationId: 12 }
  #   )
  #   result.ok            # => true / false
  #   result.error         # => nil, :missing_token, :invalid_token, "DeviceNotRegistered", :exception
  #
  # Network/parse failures never raise — they return a Result with ok: false so
  # callers (jobs) stay resilient. A "DeviceNotRegistered" error lets the caller
  # drop the stale token.
  class ExpoPushService
    EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send".freeze
    VALID_TOKEN_PREFIXES = [ "ExponentPushToken[", "ExpoPushToken[" ].freeze
    TIMEOUT_SECONDS = 5

    Result = Data.define(:ok, :error, :details)

    def self.deliver(token:, title:, body:, data: {})
      new(token: token, title: title, body: body, data: data).deliver
    end

    def initialize(token:, title:, body:, data: {})
      @token = token
      @title = title
      @body  = body
      @data  = data
    end

    def deliver
      return Result.new(ok: false, error: :missing_token, details: nil) if @token.blank?
      return Result.new(ok: false, error: :invalid_token, details: nil) unless valid_token?

      parse(post_to_expo)
    rescue StandardError => e
      Rails.logger.warn("[ExpoPush] delivery failed: #{e.class}: #{e.message}")
      Result.new(ok: false, error: :exception, details: e.message)
    end

    private

    def valid_token?
      VALID_TOKEN_PREFIXES.any? { |prefix| @token.to_s.start_with?(prefix) }
    end

    def post_to_expo
      uri = URI(EXPO_PUSH_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS

      request = Net::HTTP::Post.new(uri.path,
                                    "Content-Type" => "application/json",
                                    "Accept" => "application/json")
      request.body = {
        to: @token,
        title: @title,
        body: @body,
        data: @data,
        sound: "default",
        channelId: "default",
        priority: "high"
      }.to_json

      http.request(request)
    end

    # Expo returns { "data": { "status": "ok" | "error", "details": { "error": "DeviceNotRegistered" } } }
    def parse(response)
      body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end

      if body.dig("data", "status") == "error"
        Result.new(ok: false, error: body.dig("data", "details", "error") || :error, details: body["data"])
      else
        Result.new(ok: true, error: nil, details: body["data"])
      end
    end
  end
end
