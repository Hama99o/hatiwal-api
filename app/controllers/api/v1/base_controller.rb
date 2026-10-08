class Api::V1::BaseController < ApplicationController
  before_action :authenticate_user!
  # Runs after authentication so current_user is resolved: a user blocked while
  # holding a valid token is rejected with a clear message on every request.
  before_action :reject_blocked_user!
  # privacy-b: which ids a shop's face may carry for this client and viewer
  # (ShopFace). Public endpoints that skip authentication still resolve a token.
  before_action :set_shop_face_context
  # Which app build is calling (ClientVersionReporting). After the action, so it
  # can never delay or change a response; also covers public endpoints that
  # skip authenticate_user! but still carry a token.
  after_action :record_client_version

  private

  def set_shop_face_context
    Current.legacy_shop_ids = ShopFace.legacy_client?(platform: request.headers["X-App-Platform"],
                                                      version: request.headers["X-App-Version"])
    Current.viewer_resolver = -> { current_user }
  end

  def record_client_version
    return unless current_user

    current_user.record_client!(
      version: request.headers["X-App-Version"],
      platform: request.headers["X-App-Platform"],
      user_agent: request.user_agent
    )
  rescue StandardError => e
    Rails.logger.warn("[client-version] not recorded for user #{current_user&.id}: #{e.class}: #{e.message}")
  end
end
