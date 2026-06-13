# frozen_string_literal: true

module Api
  module V1
    module Auth
      class RegistrationsController < DeviseTokenAuth::RegistrationsController
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
