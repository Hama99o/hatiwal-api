# frozen_string_literal: true

# POST /api/v1/auth/apple — Sign in with Apple (1.1.7, iOS first; docs/APPLE_SIGN_IN.md).
#
# The app (expo-apple-authentication) sends:
#   identity_token      the JWT Apple signed (verified by Apple::IdentityToken)
#   nonce               the RAW nonce; the app passed its SHA-256 to Apple
#   authorization_code  optional; exchanged for a refresh token only so the
#                       account's Apple authorization can be revoked on deletion
#   given_name / family_name  Apple gives the name ONCE, on the first sign-in
#
# The person is found by the Apple id (`sub`) first; else an existing account is
# LINKED only when Apple says its email is verified; else a new account is
# created (the email may be a private-relay address — it is still verified).
# The response carries the same tokens as email sign-in: in the headers (like
# devise_token_auth's sign_in) and in the body (like /auth/google).
#
# A public endpoint: ApplicationController, not Api::V1::BaseController.
class Api::V1::Auth::AppleAuthController < ApplicationController
  # The other door into account creation, and each call may reach Apple.
  throttle to: 20, within: 1.hour, by: :ip, only: :create

  def create
    token = params[:identity_token].presence
    return render_coded_error("identity_token is required", code: :apple_token_missing, status: :unprocessable_entity) unless token

    claims = Apple::IdentityToken.verify(token, raw_nonce: params[:nonce])
    return render_coded_error("Invalid or expired Apple token", code: :apple_token_invalid, status: :unauthorized) unless claims

    user = User.find_by(apple_uid: claims["sub"]) || link_or_create(claims)
    return if performed?

    unless user.active_for_authentication?
      error_key = user.deleted? ? "account_deleted" : "account_#{user.status}"
      return render_ok({
        error:   error_key,
        message: user.account_blocked? ? user.account_block_message : "Account is not available",
        status:  user.status
      }, status: :forbidden)
    end

    store_refresh_token(user, params[:authorization_code])
    tokens = issue_tokens(user)
    render_ok({ data: UserSerializer.render_as_hash(user, view: :me), **tokens })
  end

  private

  def link_or_create(claims)
    email = claims["email"].to_s.strip.downcase.presence
    unless email
      render_coded_error("Apple did not share an email address", code: :apple_email_missing, status: :unprocessable_entity)
      return
    end

    existing = User.find_by(email: email)
    return link(existing, claims) if existing

    create_user(claims, email)
  end

  # Only a VERIFIED email may join an Apple id to an account that already exists.
  def link(user, claims)
    unless verified_email?(claims)
      render_coded_error("This email already has an account; sign in with it", code: :apple_email_unverified, status: :conflict)
      return
    end
    user.update_columns(apple_uid: claims["sub"], updated_at: Time.current)
    user
  end

  def create_user(claims, email)
    user = User.create(
      email: email,
      uid: email,
      provider: "apple",
      apple_uid: claims["sub"],
      firstname: params[:given_name].to_s.strip.presence || "User",
      lastname: params[:family_name].to_s.strip.presence || ".",
      password: SecureRandom.hex(24),
      status: :active,
      # Apple verifies every address it hands out, the private relay ones included.
      confirmed_at: Time.current
    )
    unless user.persisted?
      render_unprocessable_entity(user)
      return
    end
    WelcomeSupportMessageJob.enqueue_for(user)
    user
  end

  def verified_email?(claims)
    [ true, "true" ].include?(claims["email_verified"])
  end

  def store_refresh_token(user, code)
    refresh = Apple::Tokens.exchange(code)
    user.update!(apple_refresh_token: refresh) if refresh
  end

  # The same token as email sign-in, in the headers (devise_token_auth) and body.
  def issue_tokens(user)
    client_id = SecureRandom.urlsafe_base64(nil, false)
    token = user.create_token(client: client_id)
    user.save!
    response.headers.merge!(user.build_auth_headers(token.token, client_id))

    {
      "access-token": token.token,
      "token-type":   "Bearer",
      client:         client_id,
      uid:            user.uid,
      expiry:         token.expiry
    }
  end
end
