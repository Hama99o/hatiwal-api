# OFFLINE phase 2a (docs/OFFLINE_MODE.md §7.2, §10.2) — an edit that carries,
# for each field it changes, the value the user SAW (`base`). Field by field:
#   - the record still has the value they saw → apply theirs;
#   - it already has the value they want (someone made the same change) → done;
#   - otherwise → a conflict for THAT field only: it is not applied, and the
#     answer says yours / theirs / when / by whom.
# Fields without a base (and every edit from a 1.1.x app) apply as before.
module Edits
  class WithBase
    Result = Struct.new(:attrs, :conflicts, keyword_init: true)

    def self.split(record, attrs, base)
      new(record, attrs, base).split
    end

    def initialize(record, attrs, base)
      @record = record
      @attrs = attrs.to_h.stringify_keys
      @base = (base || {}).to_h.stringify_keys
    end

    def split
      conflicts = {}
      attrs = @attrs.each_with_object({}) do |(field, yours), out|
        next out[field] = yours unless @base.key?(field) && @record.has_attribute?(field)

        current = @record.public_send(field)
        if same?(field, current, @base[field])
          out[field] = yours
        elsif !same?(field, current, yours)
          conflicts[field] = conflict(field, yours, current)
        end
      end
      Result.new(attrs: attrs, conflicts: conflicts)
    end

    private

    # Compared as the column would store them ("450" == 450.0, "" == nil; false stays false).
    def same?(field, a, b)
      type = @record.class.type_for_attribute(field)
      type.cast(a == "" ? nil : a) == type.cast(b == "" ? nil : b)
    end

    def conflict(field, yours, theirs)
      # Models that track their edits (FieldEdits) say who; the others say when.
      edit = @record.respond_to?(:last_field_edit) ? @record.last_field_edit(field) : { at: @record.updated_at, by_name: nil }
      { yours: json_value(yours), theirs: json_value(theirs), changed_at: edit[:at], changed_by_name: edit[:by_name] }
    end

    # Money and other decimals as JSON numbers, like every serializer
    # (ApplicationSerializer.money): a BigDecimal would go out as "480.0".
    def json_value(value)
      value.is_a?(BigDecimal) ? value.to_f : value
    end
  end
end
