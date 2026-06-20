require "administrate/base_dashboard"

# Read-only browse of all warnings (issued from the user page, not created here).
class UserWarningDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    # admin shown as a label (there is no AdminUser dashboard to link to).
    admin_label: Field::String,
    category: Field::Select.with_options(
      searchable: false,
      collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }
    ),
    reason: Field::Text,
    expires_at: Field::DateTime,
    acknowledged_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    user
    category
    reason
    created_at
    expires_at
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    user
    admin_label
    category
    reason
    created_at
    expires_at
    acknowledged_at
    updated_at
  ].freeze

  # Issued from the user page, so the form here is empty.
  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(warning)
    "Warning ##{warning.id}"
  end
end
