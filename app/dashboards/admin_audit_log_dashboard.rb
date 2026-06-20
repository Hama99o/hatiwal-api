require "administrate/base_dashboard"

# Read-only history of admin moderation actions (accountability).
class AdminAuditLogDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    # admin_user shown as a label (there is no AdminUser dashboard to link to).
    admin_label: Field::String,
    action: Field::String,
    target_type: Field::String,
    target_id: Field::Number,
    details: Field::Text,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    created_at
    admin_label
    action
    target_type
    target_id
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    admin_label
    action
    target_type
    target_id
    details
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(log)
    "Audit ##{log.id}"
  end
end
