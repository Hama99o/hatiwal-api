require "administrate/base_dashboard"

# Read-only browse of all warnings (issued from the user page, not created here).
class UserWarningDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    # A warning strikes a user OR a shop (owner, 2026-10-16). For a shop warning,
    # `posted_by` is the team member whose listing triggered it, `listing` what.
    shop: Field::BelongsTo,
    posted_by: Field::BelongsTo.with_options(class_name: "User"),
    listing: Field::BelongsTo,
    # admin shown as a label (there is no AdminUser dashboard to link to).
    admin_label: Field::String,
    category: Field::Select.with_options(
      searchable: false,
      collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }
    ),
    reason: Field::Text,
    expires_at: Field::DateTime,
    acknowledged_at: Field::DateTime,
    # Revoke (owner, 2026-10-19).
    revoked_at: Field::DateTime,
    revoke_reason: Field::String,
    revoked_by_label: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    user
    shop
    category
    reason
    created_at
    expires_at
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    user
    shop
    posted_by
    listing
    admin_label
    category
    reason
    created_at
    expires_at
    acknowledged_at
    revoked_at
    revoke_reason
    revoked_by_label
    updated_at
  ].freeze

  # Issued from the user page, so the form here is empty.
  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(warning)
    "Warning ##{warning.id}"
  end
end
