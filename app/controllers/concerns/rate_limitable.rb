# Request rate limiting, on top of Rails' own ActionController::RateLimiting.
# No new gem and no middleware: the limits are declared per action, next to the
# action they protect.
#
# Nothing limited anything before this. Signup, login, password reset, listing
# creation, starting a conversation, sending a message and filing a report were
# all unbounded, so a single script could open thousands of accounts or bury the
# buyer feed. These limits are deliberately far above real human use — they are
# there to stop automation, not to ration the app.
#
# Declaring a limit:
#
#   throttle to: 30, within: 1.day,  by: :user, only: :create
#   throttle to: 10, within: 1.hour, by: :ip,   only: :create
#
# Choosing `by:`
#   :user keys on the authenticated user, and is right for anything behind
#   authentication — one abusive account cannot spend anyone else's quota.
#   :ip is only for the endpoints that hand out the session in the first place,
#   where there is no user yet. Keep IP limits GENEROUS: mobile users in
#   Afghanistan sit behind carrier-grade NAT, so a whole city can share one
#   address, and an IP limit tight enough to be interesting is also tight enough
#   to lock out real buyers.
module RateLimitable
  extend ActiveSupport::Concern

  # Rate limiting needs a cache store that can INCREMENT. Production uses
  # solid_cache (shared across Puma workers, which is what makes a limit real);
  # the test environment uses :null_store, whose increment always returns nil —
  # that would make every limit a silent no-op and impossible to test. So tests
  # get a dedicated in-memory store, cleared between examples by
  # spec/support/rate_limit_store.rb rather than leaking counts across the run.
  def self.store
    @store ||= Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end

  class_methods do
    def throttle(to:, within:, by: :ip, **options)
      raise ArgumentError, "throttle by: must be :ip or :user" unless [ :ip, :user ].include?(by)

      rate_limit(
        to:     to,
        within: within,
        store:  RateLimitable.store,
        # Rails requires an explicit name once a controller carries more than
        # one limit; deriving it keeps two limits on one controller from sharing
        # a counter.
        name:   "#{by}-#{to}-per-#{within.to_i}",
        by:     -> { rate_limit_key(by) },
        with:   -> { render_too_many_requests },
        **options
      )
    end
  end

  private

  # Rails' ActionController::RateLimiting#rate_limiting, wrapped so that a
  # limiter can never be the reason a request fails.
  #
  # It counts in the cache store, and this concern is the first thing in the app
  # to touch Rails.cache at all — before it, a cache outage was completely
  # harmless. It has to stay harmless: an unreachable solid_cache database must
  # not turn sign-in and signup into 500s. So this fails OPEN — the request is
  # allowed through and the error is reported. Losing a limit for the duration of
  # a cache outage is the cheaper failure by a wide margin.
  def rate_limiting(...)
    super
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :warning, context: { rate_limit: controller_path })
    nil
  end

  # Fall back to the IP when a :user limit somehow runs without a signed-in user
  # (a filter ordering change, an optionally-authenticated endpoint) so the limit
  # keeps counting instead of lumping every anonymous caller under one nil key.
  def rate_limit_key(by)
    return "ip:#{request.remote_ip}" if by == :ip

    current_user ? "user:#{current_user.id}" : "ip:#{request.remote_ip}"
  end

  def render_too_many_requests
    render json: {
      error:   "rate_limited",
      message: "Too many requests. Please wait a moment and try again."
    }, status: :too_many_requests
  end
end
