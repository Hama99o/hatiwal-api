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

  # The sitemap: just enough to list a shop page.
  view :sitemap do
    field(:updated_at) { |s| s.updated_at.iso8601 }
    field(:verified) { |s| s.verified? }
  end

  view :card do
    field(:logo_url) { |s| s.logo_url }
    field(:logo_thumb_url) { |s| s.logo_thumb_url }
    field(:verified) { |s| s.verified? }
    fields :province, :city
  end

  view :public do
    include_view :card
    fields :description, :category_id, :latitude, :longitude, :address_line, :hours, :created_at
    field(:cover_url) { |s| s.cover_url }
    field(:cover_medium_url) { |s| s.cover_medium_url }
    field(:phone) { |s| s.phone_public ? s.phone : nil }
    # SHOP-2: the apps gate "Message shop" on it. A non-member only ever gets an
    # active shop (#show 404s the rest), so it reveals nothing.
    field(:status) { |s| s.status }
    field(:category) { |s| CategorySerializer.render_as_hash(s.category) }
    # Lists pass `listings_counts:` (Shop.live_listings_counts, one grouped
    # query); a single shop page counts its own.
    # As the viewer sees them (blocks, hidden), like GET /listings?shop_id=.
    field(:listings_count) { |s, opts| opts[:listings_counts] ? opts[:listings_counts].fetch(s.id, 0) : s.listings_visible_to(opts[:current_user]).count }
    field(:verified_at) { |s| s.verified_at&.iso8601 }
    # Decided here, in the shop's own time zone, so no client guesses with the
    # phone's clock. open_now is null when the shop states no hours.
    field(:open_now) { |s| s.open_now }
    field(:next_change_at) { |s| s.next_change_at&.iso8601 }
    field(:time_zone) { |s| s.time_zone }
    field(:share_url) { |s| Shop.share_url_for(s) }
    # The SHOP's own reviews (Shop#reviews), never the owner's personal ones.
    field(:avg_rating) { |s| s.review_stats.first }
    field(:review_count) { |s| s.review_stats.last }
    # SHOP-MEDIA (docs/SHOP_MEDIA.md): up to 5 photos of the real shop + one
    # video ("▶ Video" near the top of the shop page; loads only on tap). Empty
    # / false / nil without them. Not on :card — that view rides inside listing
    # cards, conversations and invites, where the media is never shown.
    field(:has_video) { |s| s.has_video? }
    field(:video_url) { |s| s.video_url }
    field(:video_poster_url) { |s| s.video_poster_url }
    field(:video_duration_s) { |s| s.video_duration_s }
    field(:gallery_photos) { |s| s.gallery_photo_entries }
  end

  view :owner do
    include_view :public
    # Members only (moved out of :public, d0 2026-10-08, P0 privacy): the public
    # shop page is guest-readable and named the owner; the privacy text promises
    # buyers never see the owner's personal name.
    field(:owner) { |s| { id: s.owner_id, name: s.owner.full_name } }
    fields :status, :phone_public
    field(:phone) { |s| s.phone }
    # Read from the (preloaded) members, never a query per row.
    field(:role) { |s, opts| opts[:current_user] && s.shop_members.find { |m| m.user_id == opts[:current_user].id }&.role }
    # Prohibited-item strikes against the SHOP (owner, 2026-10-16) — MEMBERS ONLY,
    # never the public shop face. The banner reads these: at the threshold the
    # shop is suspended and its listings hidden.
    field(:active_warnings_count) { |s| s.active_warnings_count }
    field(:warnings_threshold) { |_s| Shop::SHOP_WARNING_BLOCK_THRESHOLD }
    field(:latest_warning) { |s| WarningJson.latest(s) }
  end
end
