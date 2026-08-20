class ListingSerializer < ApplicationSerializer
  # TASK-R418 — owner-only "who is the buyer for this reservation/sale" block.
  # Shared between :seller_list (My Listings feed row) and :owner_detailed (My
  # Listings detail + reserve/sold lifecycle response) via `field(:sale,
  # &SALE_FIELD)` so the payload shape can never drift between the two.
  #
  # A plain `proc` (never `lambda`) — Blueprinter's BlockExtractor always calls
  # `block.call(object, **local_options)`, and a lambda's strict arity would
  # raise when local_options is non-empty; a proc lenient-drops the extra args
  # exactly like every other single-arg `field(:x) { |l| ... }` in this file.
  #
  # nil when the listing has no Transaction yet (draft/active) or was
  # reserved/sold via the legacy buyer-less path — never render an empty card
  # for those on the client.
  #
  # PRIVACY: do NOT add this field to :list or :detailed — those views ship to
  # guests and to any buyer, and the buyer's identity must stay owner-scoped.
  SALE_FIELD = proc do |l|
    txn = l.current_sale
    next nil unless txn

    buyer = txn.buyer
    {
      id: txn.id,
      status: txn.status,
      final_price: txn.final_price,
      currency: txn.currency,
      completed_at: txn.completed_at,
      buyer: {
        id: buyer.id,
        name: buyer.full_name,
        avatar_url: buyer.avatar.attached? ? buyer.avatar.url : nil,
        verified: buyer.verified
      },
      # `.find_by` on an eager-loaded association still issues a query, so we
      # search the in-memory array when `conversations` is already loaded
      # (My::ListingsController#index includes it) to keep this N+1-free.
      conversation_id: if l.conversations.loaded?
                          l.conversations.to_a.find { |c| c.buyer_id == txn.buyer_id }&.id
                       else
                          l.conversations.find_by(buyer_id: txn.buyer_id)&.id
                       end
    }
  end

  fields :id, :title, :price, :currency, :status, :location, :address, :condition, :created_at

  view :list do
    fields :category_id, :views_count, :negotiable
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:image_urls) { |l| l.image_urls }
    field(:is_viewed) { |l, opts| opts[:viewed_ids]&.include?(l.id) || false }
    # TASK-BE-SAVEDLIST (FlowApp #255) — the feed heart. Before this, :list
    # never rendered is_saved at all (it only existed on :detailed), so no
    # feed card — web Bazaar or mobile Browse — could paint a filled heart
    # from the payload itself; both clients had to treat it as unknown until
    # a second `GET /my/saved_listings` round-trip landed.
    #
    # Two ways a caller can prove a row is saved, mirroring the existing
    # `viewed_ids` (is_viewed) precedent — never a per-record `exists?` here,
    # that would be an N+1 across a full page:
    #   - `saved_ids:` — a pre-computed Set for the current result set, fed by
    #     ListingsController#index/#similar via `saved_listing_ids(scope)`.
    #   - `saved_by_listing_id:` — the {listing_id => SavedListing} map the
    #     My::SavedListingsController "Saved" screen already builds for
    #     price_at_save/price_dropped; every row it renders IS a saved row by
    #     construction, so a key hit is sufficient (no extra query needed).
    # Any other :list caller that passes neither option (my/hidden_listings,
    # my/viewed_listings, users/sold_listings) gets `false` for every row —
    # a deliberate, documented scope decision (see the comments on those
    # controllers), not a silent gap.
    field(:is_saved) do |l, opts|
      next true if opts[:saved_by_listing_id]&.key?(l.id)

      opts[:saved_ids]&.include?(l.id) || false
    end
    field(:seller) do |l|
      u = l.user
      { id: l.user_id, name: u.full_name, city: u.city, verified: u.verified, avatar_url: u.avatar.attached? ? u.avatar.url : nil }
    end
    # Reuses CategorySerializer (TASK-K729 dedup fix) instead of hand-rolling
    # the same {id, name_en, name_ps, name_fa, slug} shape a 3rd time — see
    # the identical field in :seller_list and :detailed below.
    field(:category) { |l| CategorySerializer.render_as_hash(l.category) }
    # Price-drop badge data for browse feed cards. Both nil when no recent drop.
    field(:price_drop_percent) { |l| l.price_drop_percent }
    field(:price_dropped_at)   { |l| l.price_dropped_at }
    # Per-buyer "price dropped since you saved it" data — only present when the
    # controller passes a `saved_by_listing_id` map (Saved screen, TASK-Y316).
    # nil/false on every other :list surface (browse, my listings, viewed, hidden).
    field(:price_at_save) do |l, opts|
      opts[:saved_by_listing_id]&.[](l.id)&.price_at_save
    end
    field(:price_dropped) do |l, opts|
      opts[:saved_by_listing_id]&.[](l.id)&.price_dropped? || false
    end
    field(:price_drop_amount) do |l, opts|
      opts[:saved_by_listing_id]&.[](l.id)&.price_drop_amount
    end
  end

  # TASK-BE-SAVEDLIST — deliberately no `is_saved` field here. :seller_list
  # renders the seller's OWN listings (My Shop); whether the owner has
  # bookmarked their own item is not a product concept the feed heart needs
  # to answer, so this view is left alone rather than fed a `saved_ids:` Set
  # it has no use for.
  view :seller_list do
    fields :category_id, :views_count, :published_at, :reserved_at, :sold_at, :expires_at, :negotiable
    field(:thumbnail_url) { |l| l.thumbnail_url }
    field(:image_urls) { |l| l.image_urls }
    # Use .size (not .count) so that when conversations are eager-loaded via
    # includes(:conversations) in the controller the in-memory target is used
    # instead of issuing a separate COUNT(*) query per listing row.
    field(:conversations_count) { |l| l.conversations.size }
    field(:expired) { |l| l.expired? }
    field(:category) { |l| CategorySerializer.render_as_hash(l.category) }
    # Price-drop badge data for seller listing cards. Both nil when no recent drop.
    field(:price_drop_percent) { |l| l.price_drop_percent }
    field(:price_dropped_at)   { |l| l.price_dropped_at }
    # TASK-R418 — owner-only buyer/final-price block for reserved/sold rows.
    field(:sale, &SALE_FIELD)
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
        # Rating summary so the buyer sees the seller's trust score on the
        # highest-intent screen (listing detail), matching the seller profile.
        # avg_rating is nil until the seller has at least one revealed review.
        avg_rating: u.avg_rating&.to_f,
        review_count: u.review_count,
        response_rate_percent: u.response_rate_percent,
        response_time_label: u.response_time_label&.to_s,
        last_active_label: u.last_active_label&.to_s,
        # Away mode — present only when seller is CURRENTLY away (future datetime).
        # Never surfaces a stale past date; buyers only see it when seller is away.
        seller_is_away: u.away?,
        seller_away_until: u.away? ? u.away_until&.iso8601 : nil
      }
    end
    field(:category) { |l| CategorySerializer.render_as_hash(l.category) }
    # Price-drop badge data — both nil if no reduction in the last 14 days.
    field(:price_dropped_at)  { |l| l.price_dropped_at }
    field(:price_drop_percent) { |l| l.price_drop_percent }
    # Canonical share URL — https when PUBLIC_SHARE_BASE_URL env is set, else nil.
    # Mobile falls back to a hatiwal:// deep link when this is nil.
    field(:share_url) { |l| Listing.share_url_for(l) }
  end

  # TASK-R418 — the owner's own listing detail + the reserve/sold lifecycle
  # response. Everything :detailed has, PLUS the owner-only `sale` (buyer)
  # block. NEVER used for the public GET /listings/:id (guests/buyers) —
  # that stays on :detailed.
  view :owner_detailed do
    include_view :detailed
    field(:sale, &SALE_FIELD)
  end
end
