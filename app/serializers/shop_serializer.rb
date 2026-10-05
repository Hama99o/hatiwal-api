# SHOP-1 — a shop as the apps see it (hatiwal-mobile/docs/SHOPS.md).
#
#   :card    the small identity block embedded in listings and conversations
#            ("🏪 Safi Cosmetics · Shop"). Kept tiny: it rides on every feed row.
#   :public  the shop page, for anyone. The address is public on purpose — a shop
#            is a place people visit — but the phone only when phone_public.
#   :owner   :public plus what only members edit (the private phone, the status
#            while pending/suspended).
class ShopSerializer < ApplicationSerializer
  fields :id, :name

  view :card do
    field(:logo_url) { |s| s.logo_url }
    field(:verified) { |s| s.verified? }
    fields :province, :city
  end

  view :public do
    include_view :card
    fields :description, :category_id, :latitude, :longitude, :address_line, :hours, :created_at
    field(:cover_url) { |s| s.cover_url }
    field(:phone) { |s| s.phone_public ? s.phone : nil }
    field(:category) { |s| CategorySerializer.render_as_hash(s.category) }
    # Lists pass `listings_counts:` (Shop.live_listings_counts, one grouped
    # query); a single shop page counts its own.
    field(:listings_count) { |s, opts| opts[:listings_counts] ? opts[:listings_counts].fetch(s.id, 0) : s.live_listings_count }
    field(:verified_at) { |s| s.verified_at&.iso8601 }
    field(:owner) { |s| { id: s.owner_id, name: s.owner.full_name } }
    field(:share_url) { |s| Shop.share_url_for(s) }
    # The reviews of the owner count for the shop in phase 1.
    field(:avg_rating) { |s| s.owner.avg_rating&.to_f }
    field(:review_count) { |s| s.owner.review_count }
  end

  view :owner do
    include_view :public
    fields :status, :phone_public
    field(:phone) { |s| s.phone }
    # Read from the (preloaded) members, never a query per row.
    field(:role) { |s, opts| opts[:current_user] && s.shop_members.find { |m| m.user_id == opts[:current_user].id }&.role }
  end
end
