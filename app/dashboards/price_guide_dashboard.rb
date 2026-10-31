require "administrate/base_dashboard"

# IDEA-4: every price-guide bucket against the threshold (5 sales / 3 sellers
# in 90 days), so the owner sees which categories are close to switching on.
# Read-only: rebuilt nightly from sales.
class PriceGuideDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    category_name: Field::String.with_options(searchable: false),
    currency: Field::String,
    sales_vs_threshold: Field::String.with_options(searchable: false),
    sellers_vs_threshold: Field::String.with_options(searchable: false),
    available: Field::Boolean,
    low: Field::Number.with_options(decimals: 0),
    high: Field::Number.with_options(decimals: 0),
    refreshed_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[category_name currency sales_vs_threshold sellers_vs_threshold available low high refreshed_at].freeze
  SHOW_PAGE_ATTRIBUTES = COLLECTION_ATTRIBUTES
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(guide)
    "#{guide.category&.name_en} (#{guide.currency})"
  end
end
