# A finite number from a request param, or nil when it is missing or
# unreadable ("abc", "12abc", NaN, Infinity, "1e999", an array or a hash). A
# filter the client sent in a shape we cannot read is IGNORED (hunt-2, 1.1.7):
# it used to reach SQL as-is, and price_min=abc answered 500.
module NumberParam
  extend ActiveSupport::Concern

  private

  def number_param(key, integer: false)
    raw = params[key]
    return nil unless raw.is_a?(String) || raw.is_a?(Numeric)

    value = integer ? Integer(raw.to_s.strip, 10, exception: false) : Float(raw.to_s.strip, exception: false)
    value if value&.finite?
  end
end
