# frozen_string_literal: true

module Api
  module V1
    module Auth
      class RegistrationsController < DeviseTokenAuth::RegistrationsController
        # DELETE /api/v1/auth — request account deletion. We override the default
        # (which hard-destroys + cascades away the user's messages) to SCHEDULE a
        # 30-day deletion: the account is immediately hidden and logged out, but
        # recoverable by logging back in. A daily job (FinalizeAccountDeletionsJob)
        # permanently anonymizes it after the grace period, retaining messages as
        # "Deleted user". (@resource is set from the auth token by devise_token_auth.)
        def destroy
          if @resource
            @resource.schedule_deletion!
            yield @resource if block_given?
            render_destroy_success
          else
            render_destroy_error
          end
        end

        private

        def sign_up_params
          params.permit(:email, :password, :password_confirmation,
                        :firstname, :lastname, :phone, :preferred_language)
        end

        def account_update_params
          params.permit(:email, :password, :password_confirmation,
                        :current_password, :firstname, :lastname,
                        :phone, :bio, :city, :province, :preferred_language)
        end
      end
    end
  end
end
