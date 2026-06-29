class ListingSerializer < ApplicationSerializer
  fields :id, :title, :price, :currency, :status, :location, :address, :condition, :created_at

  view :list do
    fields :category_id, :views_count, :negotiable
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
    # Price-drop badge data for browse feed cards. Both nil when no recent drop.
    field(:price_drop_percent) { |l| l.price_drop_percent }
    field(:price_dropped_at)   { |l| l.price_dropped_at }
  end

  view :seller_list do
    fields :category_id, :views_count, :published_at, :reserved_at, :sold_at, :expires_at, :negotiable
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:image_urls) { |l| l.image_urls }
    # Use .size (not .count) so that when conversations are eager-loaded via
    # includes(:conversations) in the controller the in-memory target is used
    # instead of issuing a separate COUNT(*) query per listing row.
    field(:conversations_count) { |l| l.conversations.size }
    field(:expired) { |l| l.expired? }
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa }
    end
    # Price-drop badge data for seller listing cards. Both nil when no recent drop.
    field(:price_drop_percent) { |l| l.price_drop_percent }
    field(:price_dropped_at)   { |l| l.price_dropped_at }
  end

  view :detailed do
    fields :description, :category_id, :location, :latitude, :longitude,
           :views_count, :published_at, :reserved_at, :sold_at, :updated_at, :expires_at,
           :negotiable
    field(:images) { |l| l.image_urls }
    field(:image_attachments) { |l| l.image_attachments }
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:expired) { |l| l.expired? }
    field(:conversations_count) { |l| l.conversations.count }
    # Integer total only — no user identities exposed. Use .size (not .count) so
    # that when saved_listings is eager-loaded via includes(:saved_listings) in
    # the controller the in-memory target is used instead of a separate query.
    field(:saves_count) { |l| l.saved_listings.size }
    field(:is_saved) { |l, opts| opts[:current_user]&.saved_listings&.exists?(listing_id: l.id) || false }
    field(:is_viewed) do |l, opts|
      next opts[:is_viewed] unless opts[:is_viewed].nil?

      opts[:current_user]&.listing_views&.exists?(listing_id: l.id) || false
    end
    field(:seller) do |l, opts|
      u = l.user
      viewer = opts[:current_user]
      # Expose phone only to an authenticated user who is not the listing owner.
      # Guests (viewer nil) and the owner viewing their own listing both receive nil.
      phone = viewer.present? && viewer.id != l.user_id ? u.phone : nil
      {
        id: l.user_id,
        name: u.full_name,
        city: u.city,
        phone: phone,
        verified: u.verified,
        avatar_url: u.avatar.attached? ? u.avatar.url : nil,
        response_rate_percent: u.response_rate_percent,
        response_time_label: u.response_time_label&.to_s,
        last_active_label: u.last_active_label&.to_s,
        # Away mode — present only when seller is CURRENTLY away (future datetime).
        # Never surfaces a stale past date; buyers only see it when seller is away.
        seller_is_away: u.away?,
        seller_away_until: u.away? ? u.away_until&.iso8601 : nil
      }
    end
    field(:category) do |l|
      { id: l.category_id, name_en: l.category.name_en, name_ps: l.category.name_ps, name_fa: l.category.name_fa, slug: l.category.slug }
    end
    # Price-drop badge data — both nil if no reduction in the last 14 days.
    field(:price_dropped_at)  { |l| l.price_dropped_at }
    field(:price_drop_percent) { |l| l.price_drop_percent }
    # Canonical share URL — https when PUBLIC_SHARE_BASE_URL env is set, else nil.
    # Mobile falls back to a hatiwal:// deep link when this is nil.
    field(:share_url) { |l| Listing.share_url_for(l) }
  end
end
