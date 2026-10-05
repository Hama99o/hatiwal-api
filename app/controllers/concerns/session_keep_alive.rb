# Sliding login expiry (owner, 2026-10-05): "if a user comes each day he never
# needs to log in; if he doesn't come for 2 months, then we log him in".
#
# devise_token_auth gives each device token a fixed expiry from when it was
# issued (token_lifespan). After every signed-in request this pushes THAT
# device's expiry back to "now + token_lifespan", at most once a day per device,
# so an active user is never logged out and an absent one is after 2 months.
module SessionKeepAlive
  extend ActiveSupport::Concern

  REFRESH_AFTER = 1.day

  included do
    after_action :extend_session_expiry
  end

  private

  def extend_session_expiry
    user = @resource || (respond_to?(:current_user, true) && current_user)
    client = request.headers["client"].presence
    return unless user.is_a?(User) && client

    token = user.tokens&.dig(client)
    return unless token

    new_expiry = (Time.current + DeviseTokenAuth.token_lifespan).to_i
    return if new_expiry - token["expiry"].to_i < REFRESH_AFTER.to_i

    token["expiry"] = new_expiry
    user.update_column(:tokens, user.tokens)
  rescue StandardError => e
    Rails.logger.warn("[session-keep-alive] not extended for user #{user&.id}: #{e.class}: #{e.message}")
  end
end
