class ListingSerializer < ApplicationSerializer
  fields :id, :title, :price, :currency, :status, :location, :created_at

  view :list do
    fields :category_id, :views_count
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:seller) do |l|
      { id: l.user_id, name: l.user.full_name, city: l.user.city }
    end
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa, slug: l.category.slug }
    end
  end

  view :seller_list do
    fields :category_id, :views_count, :published_at, :reserved_at, :sold_at
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:conversations_count) { |l| l.conversations.count }
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa }
    end
  end

  view :detailed do
    fields :description, :category_id, :location, :latitude, :longitude,
           :views_count, :published_at, :reserved_at, :sold_at, :updated_at
    field(:images) { |l| l.image_urls }
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:is_saved) { |l, opts| opts[:current_user]&.saved_listings&.exists?(listing_id: l.id) || false }
    field(:seller) do |l|
      { id: l.user_id, name: l.user.full_name, city: l.user.city, phone: l.user.phone }
    end
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa, slug: l.category.slug }
    end
  end
end
