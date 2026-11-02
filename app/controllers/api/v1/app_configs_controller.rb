# UPD-1 — GET /api/v1/app_config (public). hatiwal-mobile/docs/FORCE_UPDATE.md
#
# Which version this app must run: the platform comes from X-App-Platform (or
# ?platform=), the version from X-App-Version (or ?version=). `status` is
# decided here ("ok" | "soft" | "blocked"); a missing or malformed version is
# always "ok". One cached row (60 s), no per-user query.
#
# NO auth at all on this endpoint, on purpose: devise_token_auth would rotate a
# signed-in app's token and put it in the response headers, and a cached
# response carrying user A's token could reach user B. So the token handling and
# the client-version recording are skipped, and the response is `private`
# (the 60 s cache lives server-side, in Rails.cache).
class Api::V1::AppConfigsController < Api::V1::BaseController
  skip_before_action :authenticate_user!
  skip_before_action :reject_blocked_user!
  skip_before_action :set_request_start, raise: false
  skip_after_action :update_auth_header, raise: false
  skip_after_action :record_client_version, raise: false
  # The auth hotfix's sliding expiry reads current_user after every action;
  # this endpoint must not touch a token at all.
  skip_after_action :extend_session_expiry, raise: false

  def show
    authorize AppReleaseSetting, :show?
    config = AppReleaseSetting.config_for(
      platform: request.headers["X-App-Platform"].presence || params[:platform],
      version: request.headers["X-App-Version"].presence || params[:version]
    )
    # Never stored by a shared cache: only the app itself may keep it 60 s.
    response.headers["Cache-Control"] = "private, max-age=60"
    response.headers["Vary"] = "X-App-Platform, X-App-Version"
    render_ok(config)
  end

  private

  # Public and the same for everyone: authorize WITHOUT resolving a user, or
  # Pundit's current_user would make devise read (and later rotate) the token.
  def pundit_user = nil
end
