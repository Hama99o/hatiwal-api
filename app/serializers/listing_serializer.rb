class ListingSerializer < ApplicationSerializer
  fields :id, :title, :price, :currency, :status, :location, :address, :condition, :created_at

  view :list do
    fields :category_id, :views_count
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:image_urls) { |l| l.image_urls }
    field(:is_viewed) { |l, opts| opts[:viewed_ids]&.include?(l.id) || false }
    field(:seller) do |l|
      u = l.user
      { id: l.user_id, name: u.full_name, city: u.city, verified: u.verified, avatar_url: u.avatar.attached? ? u.avatar.url : nil }
    end
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa, slug: l.category.slug }
    end
  end

  view :seller_list do
    fields :category_id, :views_count, :published_at, :reserved_at, :sold_at, :expires_at
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:image_urls) { |l| l.image_urls }
    field(:conversations_count) { |l| l.conversations.count }
    field(:expired) { |l| l.expired? }
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa }
    end
  end

  view :detailed do
    fields :description, :category_id, :location, :latitude, :longitude,
           :views_count, :published_at, :reserved_at, :sold_at, :updated_at, :expires_at
    field(:images) { |l| l.image_urls }
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:expired) { |l| l.expired? }
    field(:is_saved) { |l, opts| opts[:current_user]&.saved_listings&.exists?(listing_id: l.id) || false }
    field(:is_viewed) do |l, opts|
      next opts[:is_viewed] unless opts[:is_viewed].nil?

      opts[:current_user]&.listing_views&.exists?(listing_id: l.id) || false
    end
    field(:seller) do |l|
      u = l.user
      { id: l.user_id, name: u.full_name, city: u.city, phone: u.phone, verified: u.verified, avatar_url: u.avatar.attached? ? u.avatar.url : nil }
    end
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa, slug: l.category.slug }
    end
  end
end
