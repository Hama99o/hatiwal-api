class UserSerializer < ApplicationSerializer
  fields :id, :email, :firstname, :lastname, :city, :preferred_language, :created_at

  view :public do
    fields :bio, :province
    field(:full_name) { |u| u.full_name }
    field(:listings_count) { |u| u.listings.active.count }
    field(:sold_count) { |u| u.listings.sold.count }
    field(:member_since) { |u| u.created_at.strftime("%B %Y") }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
  end

  view :me do
    fields :phone, :bio, :province, :latitude, :longitude, :status, :preferred_language, :seller_mode, :preferred_theme
    field(:full_name) { |u| u.full_name }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
  end

  view :minimal do
    fields :firstname, :lastname
    field(:full_name) { |u| u.full_name }
  end
end
