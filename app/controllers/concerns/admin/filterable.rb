# Combinable index filters for the Administrate screens.
#
# WHY NOT `COLLECTION_FILTERS`. Administrate's own mechanism renders a row of
# single-choice LINKS: you cannot combine two, there are no selects, and there is
# no way to express a date or price range. It is good for one-click shortcuts the
# team uses constantly ("show me banned users") and useless as a filter system.
# Those stay where they are; this is the real bar beside them.
#
# Filters are declared per controller and applied in `scoped_resource`, so they
# compose with Administrate's own search box and with its column sorting rather
# than fighting either.
#
#   filter :status, :select, options: -> { User.statuses.keys }
#   filter :city,   :text
#   filter :created, :date_range, column: :created_at
#
# NEVER hardcode an enum's values here — pass a lambda that reads them off the
# model, so a filter can't offer a value the enum does not have.
module Admin
  module Filterable
    extend ActiveSupport::Concern

    TYPES = %i[select boolean text date_range number_range scope].freeze

    included do
      # The filter bar partial needs all four of these.
      helper_method :admin_filters, :admin_filter_values, :admin_filters_active?,
                    :resolve_options
    end

    class_methods do
      def filter(name, type, options: nil, column: nil, scope: nil, label: nil)
        raise ArgumentError, "unknown filter type #{type}" unless TYPES.include?(type)

        admin_filters << {
          name: name.to_sym, type: type, options: options,
          column: (column || name).to_sym, scope: scope,
          label: label || name.to_s.humanize
        }
      end

      def admin_filters
        @admin_filters ||= []
      end

      # Subclasses must not share the parent's array.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@admin_filters, admin_filters.dup)
      end
    end

    def admin_filters
      self.class.admin_filters
    end

    # Only the params this controller declared — never the raw query string.
    def admin_filter_values
      @admin_filter_values ||= admin_filters.each_with_object({}) do |f, acc|
        case f[:type]
        when :date_range
          acc[:"#{f[:name]}_from"] = params[:"#{f[:name]}_from"].presence
          acc[:"#{f[:name]}_to"]   = params[:"#{f[:name]}_to"].presence
        when :number_range
          acc[:"#{f[:name]}_min"] = params[:"#{f[:name]}_min"].presence
          acc[:"#{f[:name]}_max"] = params[:"#{f[:name]}_max"].presence
        else
          acc[f[:name]] = params[f[:name]].presence
        end
      end
    end

    def admin_filters_active?
      admin_filter_values.values.any?(&:present?)
    end

    private

    def scoped_resource
      admin_filters.reduce(super) { |relation, f| apply_admin_filter(relation, f) }
    end

    def apply_admin_filter(relation, filter)
      case filter[:type]
      when :select        then apply_select(relation, filter)
      when :boolean       then apply_boolean(relation, filter)
      when :text          then apply_text(relation, filter)
      when :date_range    then apply_date_range(relation, filter)
      when :number_range  then apply_number_range(relation, filter)
      when :scope         then apply_scope(relation, filter)
      else relation
      end
    end

    # Guarded against a hand-typed value: an unknown enum key would otherwise
    # raise ArgumentError and 500 the index.
    def apply_select(relation, filter)
      value = params[filter[:name]].presence
      return relation if value.blank?

      allowed = resolve_options(filter).map { |o| Array(o).last.to_s }
      return relation unless allowed.include?(value.to_s)

      relation.where(filter[:column] => value)
    end

    def apply_boolean(relation, filter)
      case params[filter[:name]].presence
      when "yes" then relation.where(filter[:column] => true)
      when "no"  then relation.where(filter[:column] => [ false, nil ])
      else relation
      end
    end

    def apply_text(relation, filter)
      value = params[filter[:name]].presence
      return relation if value.blank?

      # Escape LIKE wildcards: a typed "%" or "_" is a literal, not "match all".
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
      relation.where(relation.arel_table[filter[:column]].matches(pattern))
    end

    def apply_date_range(relation, filter)
      from = parse_date(params[:"#{filter[:name]}_from"])
      to   = parse_date(params[:"#{filter[:name]}_to"])
      relation = relation.where(filter[:column] => from.beginning_of_day..) if from
      relation = relation.where(filter[:column] => ..to.end_of_day) if to
      relation
    end

    def apply_number_range(relation, filter)
      min = params[:"#{filter[:name]}_min"].presence
      max = params[:"#{filter[:name]}_max"].presence
      relation = relation.where(filter[:column] => min.to_f..) if min
      relation = relation.where(filter[:column] => ..max.to_f) if max
      relation
    end

    def apply_scope(relation, filter)
      value = params[filter[:name]].presence
      return relation if value.blank?

      lambda_for = filter[:scope]
      return relation unless lambda_for.respond_to?(:call)

      lambda_for.call(relation, value) || relation
    end

    def resolve_options(filter)
      opts = filter[:options]
      opts.respond_to?(:call) ? opts.call : Array(opts)
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
