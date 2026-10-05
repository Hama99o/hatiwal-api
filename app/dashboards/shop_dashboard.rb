require "administrate/base_dashboard"

# SHOP-1 — admin shops (hatiwal-mobile/docs/SHOPS.md, "Admin"). Logo/cover are
# Active Storage and are shown by the custom show page, not as fields.
# Search covers the shop name and the owner's name, email and phone.
class ShopDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    owner: Field::BelongsTo.with_options(searchable: true, searchable_fields: %w[firstname lastname email phone]),
    category: Field::BelongsTo,
    description: Field::Text,
    province: Field::String,
    city: Field::String,
    address_line: Field::String,
    latitude: Field::Number.with_options(decimals: 6),
    longitude: Field::Number.with_options(decimals: 6),
    phone: Field::String,
    phone_public: Field::Boolean,
    status: Field::Select.with_options(
      searchable: false,
      collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }
    ),
    verified_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name owner category province status verified_at created_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id name owner category description province city address_line latitude longitude
    phone phone_public status verified_at created_at updated_at
  ].freeze

  # Admins moderate shops (suspend, members, badge); they do not edit them.
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(shop) = "#{shop.name} (shop ##{shop.id})"
end
