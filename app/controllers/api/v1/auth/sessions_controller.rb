# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < DeviseTokenAuth::SessionsController
        # Clear the push token on logout so this device stops receiving
        # notifications for the departing user. Without this, a second account
        # logging in on the same device shares the token and receives
        # notifications intended for the logged-out account.
        def destroy
          current_user&.update_column(:push_token, nil)
          super
        end

        private

        # User#active_for_authentication? returns false for suspended/banned
        # accounts, which devise_token_auth funnels through the generic
        # "not confirmed" error. Override it so a blocked user is told the real
        # reason (status + admin message) instead.
        def render_create_error_not_confirmed
          if @resource&.account_blocked?
            render_error(
              403,
              @resource.account_block_message,
              status: @resource.status,
              reason: @resource.block_reason
            )
          else
            super
          end
        end
      end
    end
  end
end
