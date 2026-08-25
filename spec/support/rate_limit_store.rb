# Rate limits (RateLimitable) count in a real in-memory cache during tests: the
# test environment's :null_store returns nil from #increment, which would make
# every limit a silent no-op and impossible to assert on.
#
# That store is process-wide, so it has to be cleared between examples —
# otherwise counts accumulate across the whole run and, for instance, the 21st
# `auth_headers_for` call in the suite would start coming back 429.
RSpec.configure do |config|
  config.before { RateLimitable.store.clear }
end
