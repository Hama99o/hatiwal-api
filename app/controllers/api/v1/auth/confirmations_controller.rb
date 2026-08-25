# frozen_string_literal: true

module Api
  module V1
    module Auth
      # DTA's ConfirmationsController#show ends with a bare `redirect_to` to
      # `default_confirm_success_url`, and its `redirect_options` hook returns an
      # empty hash. That URL is on a different host from this API (it is a page in
      # the web app), and since Rails 7 a cross-host redirect raises
      # ActionController::Redirecting::OpenRedirectError — so every user who
      # tapped the link in their confirmation email got a 500, even though
      # `confirm_by_token` had already succeeded a few lines earlier. Confirmed,
      # and the reason this class exists.
      #
      # Allowing the redirect is therefore necessary. Doing it with a bare
      # `allow_other_host: true` would NOT be safe: DTA takes the destination from
      # `params[:redirect_url]` in PREFERENCE to the configured one, so "allow any
      # host" plus "host chosen by the caller" is a textbook open redirect — a
      # link that reads as a Hatiwal confirmation and lands the user on someone
      # else's page.
      #
      # So the redirect is allowed and the destination is pinned: a redirect_url
      # param is honoured only while it points at the configured host, and
      # anything else falls back to the configured URL.
      class ConfirmationsController < DeviseTokenAuth::ConfirmationsController
        private

        def redirect_options
          { allow_other_host: true }
        end

        def redirect_url
          configured = DeviseTokenAuth.default_confirm_success_url
          requested  = params[:redirect_url].presence
          return configured if requested.blank?

          same_host?(requested, configured) ? requested : configured
        end

        def same_host?(candidate, configured)
          URI.parse(candidate).host == URI.parse(configured).host
        rescue URI::InvalidURIError, TypeError
          false
        end
      end
    end
  end
end
