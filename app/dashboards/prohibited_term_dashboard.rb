require "administrate/base_dashboard"

# "Prohibited terms" (owner, 2026-10-13): the words that open a Flag. Terms are
# stored normalized (ي→ی, ك→ک, no harakat / ZWNJ, lowercase), so the list shows
# exactly what is compared. A trailing "*" = "words starting with".
class ProhibitedTermDashboard < Administrate::BaseDashboard
  ENUM = ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }

  ATTRIBUTE_TYPES = {
    id: Field::Number,
    term: Field::String.with_options(searchable: true),
    locale: Field::Select.with_options(searchable: false, collection: ENUM),
    category: Field::Select.with_options(searchable: false, collection: ENUM),
    note: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[term locale category note updated_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id term locale category note created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[term locale category note].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(term)
    "“#{term.term}”"
  end
end
