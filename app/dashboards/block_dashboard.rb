require "administrate/base_dashboard"

# Read-only view of user-to-user blocks (one person blocking another for
# privacy — distinct from an admin ban). Issued by users in the app, not here.
class BlockDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    blocker: Field::BelongsTo,
    blocked: Field::BelongsTo,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    blocker
    blocked
    created_at
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    blocker
    blocked
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(block)
    "Block ##{block.id}"
  end
end
