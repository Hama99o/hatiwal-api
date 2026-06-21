require "administrate/base_dashboard"

# Manage admin (staff) accounts. Sensitive auth columns (encrypted_password,
# reset/unlock tokens, failed_attempts) are intentionally never shown or edited.
# Password uses Field::Password — blank on edit means "keep current" (handled in
# Admin::AdminUsersController).
class AdminUserDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    email: Field::Email,
    password: Field::Password,
    sign_in_count: Field::Number,
    current_sign_in_at: Field::DateTime,
    last_sign_in_at: Field::DateTime,
    last_sign_in_ip: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    email
    last_sign_in_at
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    email
    sign_in_count
    current_sign_in_at
    last_sign_in_at
    last_sign_in_ip
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    email
    password
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(admin_user)
    admin_user.name.presence || admin_user.email
  end
end
