# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < DeviseTokenAuth::SessionsController
        # Devise's :lockable is not enabled, so nothing bounded password
        # guessing at all. Per-IP rather than per-email: an attacker rotating
        # emails is exactly the case worth stopping.
        throttle to: 20, within: 5.minutes, by: :ip, only: :create

        # Clear the push token on logout so this device stops receiving
        # notifications for the departing user. Without this, a second account
        # logging in on the same device shares the token and receives
        # notifications intended for the logged-out account.
        #
        # P0 login race (2026-10-06): DTA deletes this client from the user it
        # loaded at the START of the request and saves the whole `tokens` hash.
        # A sign-in of the same user committing in between (the app signing out
        # and straight back in) was wiped by that stale save, so the sign-in
        # answered 200 with no auth headers and a dead session. Re-read the row
        # under a lock first: the delete then runs on the current tokens, and
        # DTA's sign-in (create_and_assign_token, also with_lock) waits for it.
        def destroy
          current_user&.update_column(:push_token, nil)
          ActiveRecord::Base.transaction do
            @resource&.lock!
            super
          end
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
              reason: @resource.display_block_reason
            )
          else
            super
          end
        end
      end
    end
  end
end
