# UPD-1 — app version strings ("1.1.5"), compared numerically part by part, so
# "1.10.0" > "1.9.9". The mobile app has the same table (src/lib/appVersion.ts).
#
# A missing or malformed version never blocks anyone: callers treat nil as
# "unknown" and fall through to `ok` (docs/FORCE_UPDATE.md, safety rule 4).
module AppVersion
  FORMAT = ClientVersionReporting::VERSION_FORMAT

  module_function

  # [1, 1, 5] for "1.1.5", padded to 4 parts; nil for anything else.
  def parse(raw)
    str = raw.to_s.strip
    return nil unless FORMAT.match?(str)

    parts = str.split(".").map(&:to_i)
    parts.fill(0, parts.length...4)
  end

  def valid?(raw) = !parse(raw).nil?

  # -1, 0 or 1; nil when either side is not a version.
  def compare(left, right)
    a = parse(left)
    b = parse(right)
    return nil if a.nil? || b.nil?

    a <=> b
  end

  def below?(version, threshold)
    compare(version, threshold) == -1
  end
end
