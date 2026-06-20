require "administrate/base_dashboard"

# The ActiveStorage image association (images_attachments / images_blobs) is
# omitted — Administrate has no dashboard for attachments and would raise on the
# show/edit pages. Admins moderate listing content + lifecycle here.
class ListingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    title: Field::String,
    user: Field::BelongsTo,
    category: Field::BelongsTo,
    price: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    condition: Field::Select.with_options(
      searchable: false,
      collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }
    ),
    status: Field::Select.with_options(
      searchable: false,
      collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }
    ),
    location: Field::String,
    description: Field::Text,
    views_count: Field::Number,
    removed_at: Field::DateTime,
    removed_reason: Field::Text,
    published_at: Field::DateTime,
    reserved_at: Field::DateTime,
    sold_at: Field::DateTime,
    expires_at: Field::DateTime,
    reports: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    title
    user
    price
    status
    created_at
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    user
    category
    price
    currency
    condition
    status
    location
    description
    views_count
    removed_at
    removed_reason
    published_at
    reserved_at
    sold_at
    expires_at
    reports
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    title
    category
    price
    currency
    condition
    status
    location
    description
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(status: :active) },
    sold: ->(resources) { resources.where(status: :sold) },
    reserved: ->(resources) { resources.where(status: :reserved) },
    draft: ->(resources) { resources.where(status: :draft) }
  }.freeze

  def display_resource(listing)
    listing.title.presence || "Listing ##{listing.id}"
  end
end
