class UserSerializer < ApplicationSerializer
  fields :id, :email, :firstname, :lastname, :city, :preferred_language, :created_at

  view :public do
    fields :bio, :province
    field(:full_name) { |u| u.full_name }
    field(:listings_count) { |u| u.listings.active.count }
  end

  view :me do
    fields :phone, :bio, :province, :latitude, :longitude, :status, :preferred_language
    field(:full_name) { |u| u.full_name }
  end

  view :minimal do
    fields :firstname, :lastname
    field(:full_name) { |u| u.full_name }
  end
end
