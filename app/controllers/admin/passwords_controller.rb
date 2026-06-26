# frozen_string_literal: true

# Admin password reset using Devise's :recoverable module.
#
# This inherits from ActionController::Base (same as Admin::SessionsController)
# rather than Devise::PasswordsController because the app runs in api_only mode,
# which makes DeviseController inherit ActionController::API — losing `layout`,
# view rendering, and flash support that the server-rendered admin needs.
module Admin
  class PasswordsController < ActionController::Base
    include Devise::Controllers::Helpers

    protect_from_forgery with: :exception
    layout "admin/auth"

    # GET /admin/password/new
    def new
      @resource = AdminUser.new
    end

    # POST /admin/password
    def create
      @resource = AdminUser.find_by(email: params.dig(:admin_user, :email)&.strip&.downcase)

      if @resource
        @resource.send_reset_password_instructions
      end

      # Always redirect regardless of whether the email was found to avoid
      # revealing whether an address is registered.
      redirect_to new_admin_user_session_path,
                  notice: "If that email is registered you will receive reset instructions shortly."
    end

    # GET /admin/password/edit
    def edit
      @resource = AdminUser.with_reset_password_token(params[:reset_password_token])

      if @resource.nil? || !@resource.reset_password_period_valid?
        redirect_to new_admin_user_password_path, alert: "Reset link is invalid or has expired."
      end
    end

    # PUT /admin/password
    def update
      @resource = AdminUser.with_reset_password_token(reset_params[:reset_password_token])

      if @resource.nil? || !@resource.reset_password_period_valid?
        @resource ||= AdminUser.new
        @resource.errors.add(:reset_password_token, "is invalid or has expired")
        return render :edit, status: :unprocessable_entity
      end

      if @resource.reset_password(reset_params[:password], reset_params[:password_confirmation])
        redirect_to new_admin_user_session_path, notice: "Password updated. Please sign in."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def reset_params
      params.require(:admin_user).permit(:reset_password_token, :password, :password_confirmation)
    end
  end
end
