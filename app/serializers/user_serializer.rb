class UserSerializer < ApplicationSerializer
  # Only :id is in the base — all other fields are scoped to their view
  # to prevent PII (email, phone, location) leaking into the :public view.
  fields :id

  # :public — trust-dossier shown to any authenticated user looking at a seller.
  # Must NOT include email, phone, exact coordinates, or any other PII.
  view :public do
    fields :bio, :verified
    # Province and city are the user's OWN address, so they obey their own
    # visibility setting. Owner request, 2026-09-02: "show option to show number
    # and address to people or not, I mean user address not list address its
    # important". A LISTING's location is a separate field and is unaffected — a
    # seller hiding their home must not blank out where the item can be collected.
    field(:province) { |u| u.show_address_publicly ? u.province : nil }
    field(:city) { |u| u.show_address_publicly ? u.city : nil }
    field(:firstname) { |u| u.firstname }
    field(:lastname) { |u| u.lastname }
    field(:full_name) { |u| u.full_name }
    # Must equal what the buyer grid under this header actually returns —
    # `GET /listings?user_id=` runs `Listing.browsable`. Fixed once already for
    # this exact class of bug (TASK-B903, expired listings inflating the count);
    # SF-B1's widening of `browsable` to include reserved listings reopened it,
    # so this now tracks `live` too.
    field(:listings_count) { |u| u.live_listings_count }
    # TASK-TX02 — denormalized counters (users.sold_count / users.bought_count),
    # bumped by Transaction#bump_trust_counters! on every completed sale. Plain
    # column reads: zero extra queries here, so a public-profile load AND a list
    # of many profiles (e.g. GET /blocks) both stay N+1-free for these stats.
    field(:sold_count) { |u| u.sold_count }
    field(:bought_count) { |u| u.bought_count }
    field(:avg_rating) { |u| u.avg_rating&.to_f }
    field(:review_count) { |u| u.review_count }
    # English month names for every reader (the API does not switch locale);
    # kept for older apps. `member_since_at` is the month as a date, for the
    # apps to format in the reader's language — month precision only, never the
    # exact sign-up time (edge pass 1.1.6, 2026-10-08).
    field(:member_since) { |u| u.created_at.strftime("%B %Y") }
    field(:member_since_at) { |u| u.created_at.to_date.beginning_of_month.iso8601 }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
    # Whether the current viewer has blocked this user. Keeps the block/unblock
    # toggle in sync on first open without a separate API call. Defaults to false
    # when no viewer context is available (e.g. unauthenticated — should not
    # happen in practice since the endpoint requires auth).
    # A list that already knows the answer passes `blocked_ids` (GET /blocks: all of them).
    field(:blocked) { |u, opts| opts[:blocked_ids] ? opts[:blocked_ids].include?(u.id) : (opts[:current_user]&.blocked?(u) || false) }

    # Response rate trust signal — nil when threshold (5 conversations) not met.
    field(:response_rate_percent) { |u| u.response_rate_percent }
    field(:response_time_label) { |u| u.response_time_label&.to_s }

    # Privacy-safe recency signal — coarse bucket, never the raw timestamp.
    # "today" | "this_week" | "this_month" | null (long-dormant or no sign-in).
    field(:last_active_label) { |u| u.last_active_label&.to_s }

    # Away mode — present only when the seller is CURRENTLY away (away_until is
    # a future datetime). Never surfaces a stale past date to buyers.
    field(:is_away) { |u| u.away? }
    field(:away_until) { |u| u.away? ? u.away_until&.iso8601 : nil }

    # Canonical share URL — https when PUBLIC_SHARE_BASE_URL env is set, else nil.
    # Mobile falls back to a hatiwal://seller/<id> deep link when this is nil.
    # Only exposed in :public view — never in :me or :minimal (owners share via the
    # listing share flow; the :public view is already gated to publicly-active users).
    field(:share_url) { |u| User.profile_share_url_for(u) }
  end

  # :me — full private profile for the authenticated user viewing their own data.
  # Includes PII (email, phone, coordinates) since the owner is entitled to see it.
  view :me do
    fields :email, :firstname, :lastname, :city,
           :phone, :bio, :province, :latitude, :longitude,
           :status, :preferred_language, :seller_mode, :preferred_theme, :verified,
           :created_at, :deletion_scheduled_at,
           # The user's own contact details and visibility switches, so the
           # clients can render the inputs. Only ever in :me — never :public.
           :whatsapp_number, :show_phone_publicly, :show_address_publicly
    field(:full_name) { |u| u.full_name }
    field(:avatar_url) { |u| u.avatar.attached? ? u.avatar.url : nil }
    # Whether this account's email address has been confirmed.
    #
    # A BOOLEAN, not `confirmed_at`: the clients only need to decide whether to show
    # the "confirm your email" prompt, and the timestamp is not theirs to display.
    #
    # Without this the prompt could not exist at all — :confirmable has been on since
    # the backend work, but no client could tell a confirmed account from an
    # unconfirmed one, which is why nothing was ever gated on it
    # (docs/EMAIL_CONFIRMATION.md).
    field(:email_confirmed) { |u| u.confirmed_at.present? }
    # The badge on "My invitations" (GET /my/shop_invites, same scope).
    field(:pending_shop_invites_count) { |u| ShopInvite.addressed_to(u).count }
    # Dashboard stats for the user's own profile.
    # SF-B1 — `live`, matching `listings_count` above and the widened
    # `browsable`/"Active" tab. A held listing is still one of the seller's items
    # on sale; counting it as neither active nor anything else made the dashboard
    # tile disagree with the tab right next to it.
    # Personal only, whatever "Sell as" is (owner, 2026-10-07): a shop's
    # products are counted on the shop, never on the person's Profile.
    field(:items_active_count) { |u| u.listings.personal.live.count }
    field(:items_sold_count) { |u| u.listings.personal.sold.count }
    # No money total: listings span currencies (AFN/USD/EUR) with no FX rate, so
    # summing them would be meaningless. We surface counts only.
    field(:saved_items_count) { |u| u.saved_listings.count }
    # TASK-TX02 — trust stats sourced from the transactions table (a real sale
    # with a confirmed counterparty), distinct from items_sold_count above
    # (which counts listing.status == sold regardless of whether a buyer was
    # ever identified). Plain column reads — no extra query.
    field(:sold_count) { |u| u.sold_count }
    field(:bought_count) { |u| u.bought_count }
    field(:avg_rating) { |u| u.avg_rating&.to_f }
    field(:review_count) { |u| u.review_count }
    field(:unread_message_count) do |u|
      # Exclude conversations the user has archived — archiving should silence the badge.
      conversation_ids = Conversation.for_user(u).not_archived_for(u).select(:id)
      Message.joins(:conversation).where(conversation_id: conversation_ids, read_at: nil)
             .where(Conversation.inbound_message_sql_for(u), u: u.id).count
    end
    # Strike status so the app can show a "X of N warnings" banner from the
    # /users/me payload without an extra request.
    field(:active_warnings_count) { |u| u.active_warnings_count }
    field(:warning_threshold) { |_u| User::WARNING_BLOCK_THRESHOLD }
    # Away mode — expose the computed away? flag and the datetime (as ISO-8601)
    # when the seller is CURRENTLY away. Returns nil when not away so the edit
    # toggle knows to show "off" state. Owner can set a new future date via PUT /users/me.
    field(:is_away) { |u| u.away? }
    field(:away_until) { |u| u.away? ? u.away_until&.iso8601 : nil }
    # LOC-1 — where the Bazaar and the map pickers centre for this user:
    # own address → guessed → Kabul (User#effective_location). The clients read
    # this block and never re-implement the rule. Only in :me — the guessed
    # location must never reach :public, :minimal or a listing.
    field(:location) { |u| u.effective_location }
    # SHOP-1 — who the user sells as in Seller mode (null = Me), already checked
    # against membership and the shop's status (User#selling_shop), and the
    # shops they can sell as, for the "Sell as" sheet. Two small queries.
    # Users with no shop (almost everyone) cost ZERO extra queries here:
    # shop_memberships_count is a column (ShopMember counter_cache).
    field(:selling_as_shop) { |u| (shop = u.selling_shop) && ShopSerializer.render_as_hash(shop, view: :card) }
    field(:unread_counts) { |u| u.shop_memberships_count.positive? ? u.unread_counts : nil }
    field(:shops) do |u|
      next [] unless u.shop_memberships_count.positive?

      # SHOP-2: owned first, then oldest first — a stable "Sell as" order.
      u.shop_members.includes(shop: { logo_attachment: :blob }).joins(:shop)
       .order(Arel.sql("CASE WHEN shops.owner_id = #{u.id.to_i} THEN 0 ELSE 1 END"), "shops.created_at", "shops.id").map do |m|
        ShopSerializer.render_as_hash(m.shop, view: :card).merge(role: m.role, status: m.shop.status)
      end
    end
  end

  view :minimal do
    fields :firstname, :lastname
    field(:full_name) { |u| u.full_name }
  end
end
