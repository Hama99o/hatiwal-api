# frozen_string_literal: true

class Api::V1::Auth::PasswordsController < DeviseTokenAuth::PasswordsController
  # DTA validates redirect_url before create — we skip it because our
  # PasswordsController manages the reset URL internally via WEB_RESET_URL env var.
  skip_before_action :validate_redirect_url_param, only: [ :create ], raise: false

  # POST /api/v1/auth/password
  # Generates a reset token and sends our branded email instead of the
  # default devise_token_auth email.
  def create
    return render_create_error_missing_email unless resource_params[:email]

    @email = get_case_insensitive_field_from_resource_params(:email)
    return render_create_error_missing_email if @email.blank?

    @resource = resource_class.dta_find_by(uid: @email, provider: "email")

    if @resource
      raw_token, hashed_token = Devise.token_generator.generate(resource_class, :reset_password_token)
      @resource.update!(
        reset_password_token: hashed_token,
        reset_password_sent_at: Time.now.utc
      )
      UserMailer.reset_password(@resource, raw_token).deliver_later
      render_create_success
    else
      render_not_found_error
    end
  end
end
