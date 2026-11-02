class Listing
  # The typed `details` of a stay (docs/STAYS_DESIGN.md §2.3): a room's guests,
  # beds, bathroom, amenities and check-in/out. Every key is optional (the
  # shipped 1.1.6 app sends none); an unknown key or a bad value is an error.
  #
  #   Listing::StayDetails.normalize("guests" => "2", "amenities" => ["wifi"])
  #   # => { "guests" => 2, "amenities" => ["wifi"] }
  class StayDetails
    AMENITIES = %w[wifi heating ac hot_water parking breakfast kitchen tv power_backup family_only].freeze
    BATHROOMS = %w[private shared].freeze
    COUNTS = { "guests" => 1..50, "beds" => 0..50 }.freeze
    TIMES = %w[check_in check_out].freeze
    KEYS = (COUNTS.keys + %w[bathroom amenities] + TIMES).freeze
    TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

    # Strings from a form become integers / a de-duplicated list; blanks drop out.
    def self.normalize(raw)
      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      hash.each_with_object({}) do |(key, value), out|
        key = key.to_s
        next if value.nil? || value == "" || value == []

        normalized =
          if COUNTS.key?(key) then integer(value)
          elsif key == "amenities" then Array(value).map(&:to_s).reject(&:empty?).uniq
          else value.to_s.strip
          end
        # A form clearing every amenity sends one blank: nothing left, no key.
        out[key] = normalized unless normalized == [] || normalized == ""
      end
    end

    # Error messages (empty when valid) for an already-normalized hash.
    def self.errors_for(details)
      errors = []
      unknown = details.keys - KEYS
      errors << "has unknown keys: #{unknown.join(', ')}" if unknown.any?
      COUNTS.each do |key, range|
        next unless details.key?(key)

        errors << "#{key} must be a whole number from #{range.min} to #{range.max}" unless details[key].is_a?(Integer) && range.cover?(details[key])
      end
      if details.key?("bathroom") && !BATHROOMS.include?(details["bathroom"])
        errors << "bathroom must be one of: #{BATHROOMS.join(', ')}"
      end
      if details.key?("amenities")
        bad = Array(details["amenities"]) - AMENITIES
        errors << "amenities must be among: #{AMENITIES.join(', ')} (got #{bad.join(', ')})" if bad.any? || !details["amenities"].is_a?(Array)
      end
      TIMES.each do |key|
        next unless details.key?(key)

        errors << "#{key} must be a time like 14:00" unless details[key].to_s.match?(TIME_FORMAT)
      end
      errors
    end

    def self.integer(value)
      Integer(value.to_s, 10)
    rescue ArgumentError, TypeError
      value
    end
    private_class_method :integer
  end
end
