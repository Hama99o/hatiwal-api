require "administrate/base_dashboard"

# Curated on purpose. Auth internals (encrypted_password, tokens,
# reset_password_token, unlock_token, confirmation_token, provider/uid) and the
# ActiveStorage avatar association are deliberately omitted: they must never be
# viewed or edited through the admin UI. Admins manage identity + moderation
# fields (status, verified, seller_mode) only.
class UserDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    firstname: Field::String,
    lastname: Field::String,
    email: Field::String,
    phone: Field::String,
    city: Field::String,
    province: Field::String,
    bio: Field::Text,
    preferred_language: Field::String,
    seller_mode: Field::Boolean,
    verified: Field::Boolean,
    status: Field::Select.with_options(
      searchable: false,
      collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }
    ),
    block_reason: Field::Text,
    listings: Field::HasMany,
    filed_reports: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    firstname
    lastname
    email
    status
    verified
    seller_mode
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    firstname
    lastname
    email
    phone
    city
    province
    bio
    preferred_language
    seller_mode
    verified
    status
    block_reason
    listings
    filed_reports
    created_at
    updated_at
  ].freeze

  # Editable fields only — no credentials. `status` drives moderation
  # (active / suspended / banned) and `verified` toggles the trust badge.
  FORM_ATTRIBUTES = %i[
    firstname
    lastname
    email
    phone
    city
    province
    bio
    preferred_language
    seller_mode
    verified
    status
    block_reason
  ].freeze

  COLLECTION_FILTERS = {
    verified: ->(resources) { resources.where(verified: true) },
    sellers: ->(resources) { resources.where(seller_mode: true) },
    suspended: ->(resources) { resources.where(status: :suspended) },
    banned: ->(resources) { resources.where(status: :banned) }
  }.freeze

  def display_resource(user)
    [ user.full_name.presence, user.email ].compact.first || "User ##{user.id}"
  end
end
