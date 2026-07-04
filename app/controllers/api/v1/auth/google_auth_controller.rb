# frozen_string_literal: true

# POST /api/v1/auth/google
#
# Mobile flow (mirrors MultiMagic's OauthServicesController but adapted for
# a pure-JSON mobile API):
#
#   1. Mobile app (Expo / React Native) performs Google Sign-In and receives
#      an ID token from Google's SDK.
#   2. Mobile POSTs { id_token: "..." } to this endpoint.
#   3. We verify the token with Google's tokeninfo API (same approach MultiMagic
#      uses, just with an ID token instead of an authorization code).
#   4. We find or create the User record.
#   5. We generate devise_token_auth tokens and return them in the JSON body
#      together with the user payload — the mobile stores them in AsyncStorage.
#
# Inherits from ApplicationController (not Api::V1::BaseController) so that
# authenticate_user! is NOT fired — Google login is a public endpoint.
class Api::V1::Auth::GoogleAuthController < ApplicationController
  GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"

  def create
    id_token = params[:id_token].presence
    return render json: { error: "id_token is required" }, status: :unprocessable_entity if id_token.nil?

    google_payload = verify_google_id_token(id_token)
    return render json: { error: "Invalid or expired Google token" }, status: :unauthorized unless google_payload

    # Google should provide a verified email address
    unless google_payload[:email_verified].to_s == "true"
      return render json: { error: "Google account email is not verified" }, status: :unauthorized
    end

    user = find_or_create_user(google_payload)
    return render json: { errors: user.errors.full_messages }, status: :unprocessable_entity unless user.persisted?

    # Block suspended/banned/deleted accounts — same guard as email login
    unless user.active_for_authentication?
      error_key = user.deleted? ? "account_deleted" : "account_#{user.status}"
      return render json: {
        error:   error_key,
        message: user.account_blocked? ? user.account_block_message : "Account is not available",
        status:  user.status
      }, status: :forbidden
    end

    tokens = issue_tokens(user)

    render json: {
      data: UserSerializer.render_as_hash(user, view: :me),
      **tokens
    }, status: :ok
  end

  private

  def verify_google_id_token(id_token)
    response = Faraday.get(GOOGLE_TOKENINFO_URL, { id_token: id_token })
    return nil unless response.status == 200

    payload = JSON.parse(response.body).symbolize_keys
    return nil unless valid_audience?(payload[:aud])

    payload
  rescue StandardError => e
    Rails.logger.error("Google token verification error: #{e.message}")
    nil
  end

  # Accept tokens from the web client OR the iOS client (iOS OAuth tokens have
  # aud = iOS client ID, not the web client ID).
  #
  # FAIL CLOSED in production: if the client ids are missing from credentials,
  # reject every token rather than accepting ANY Google-issued token — an
  # attacker could otherwise mint a token from their own OAuth app and sign in
  # as (or auto-create) any account matching the token's email. The permissive
  # branch survives only for development/test convenience.
  def valid_audience?(aud)
    web = Rails.application.credentials[:google_client_id]
    ios = Rails.application.credentials[:google_ios_client_id]
    allowed = [ web, ios ].compact_blank

    if allowed.empty?
      Rails.logger.error("Google auth: google_client_id missing from credentials — rejecting token") if Rails.env.production?
      return !Rails.env.production?
    end

    allowed.include?(aud)
  end

  def find_or_create_user(payload)
    email = payload[:email]&.strip&.downcase
    return User.new.tap { |u| u.errors.add(:email, "not provided by Google") } if email.blank?

    # If the user already has an account (any provider), sign them in directly
    # without changing their provider — they keep their email+password login too.
    User.find_by(email: email) || create_user_from_google(payload, email)
  end

  def create_user_from_google(payload, email)
    User.create(
      email: email,
      uid: email,
      provider: "google",
      firstname: payload[:given_name].presence || "User",
      lastname: payload[:family_name].presence || ".",
      password: SecureRandom.hex(24),
      status: :active
    )
  end

  def issue_tokens(user)
    client_id = SecureRandom.urlsafe_base64(nil, false)
    token     = user.create_token(client: client_id)
    user.save!

    {
      "access-token": token.token,
      "token-type":   "Bearer",
      client:         client_id,
      uid:            user.uid,
      expiry:         token.expiry
    }
  end
end
