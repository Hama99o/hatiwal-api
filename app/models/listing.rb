class Listing < ApplicationRecord
  belongs_to :user
  belongs_to :category
  has_many_attached :images
  has_many :saved_listings, dependent: :destroy
  has_many :listing_views, dependent: :destroy
  has_many :conversations, dependent: :nullify
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :price_histories, class_name: ListingPriceHistory.name, dependent: :destroy
  has_many :hidden_listings, dependent: :destroy

  enum :status, { draft: 0, active: 1, reserved: 2, sold: 3 }
  # Optional item condition. Keys avoid the reserved word `new` (would clash
  # with Listing.new); the mobile app maps them to "New / Like new / Good / Fair".
  enum :condition, { brand_new: 0, like_new: 1, good: 2, fair: 3 }, prefix: :condition

  validates :title, presence: true, length: { maximum: 150 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  CURRENCIES = %w[AFN USD EUR].freeze
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :category, presence: true

  EARTH_RADIUS_KM = 6371
  # How long a published listing stays in the buyer feed before it expires.
  LISTING_LIFESPAN = 30.days

  # Valid sort keys accepted by the API. "nearest" additionally requires
  # latitude/longitude — the controller applies `nearest_first` for it and
  # falls back to the default (newest) ordering when coordinates are absent.
  SORT_KEYS = %w[newest oldest price_asc price_desc most_viewed nearest].freeze

  scope :active,      -> { where(status: :active) }
  scope :ordered,     -> { order(created_at: :desc) }
  scope :by_category, ->(id) { where(category_id: id) }
  scope :by_seller,   ->(id) { where(user_id: id) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :not_removed, -> { where(removed_at: nil) }
  scope :expired_active, -> { active.where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }

  # Sort the result set by the supplied key. Falls back to newest (created_at
  # desc) for any absent or unrecognised value — the SORT_KEYS whitelist prevents
  # injection and keeps sort semantics clearly defined in one place.
  scope :sorted, lambda { |key|
    case key.to_s
    when "price_asc"   then reorder(price: :asc)
    when "price_desc"  then reorder(price: :desc)
    when "oldest"      then reorder(created_at: :asc)
    when "most_viewed" then reorder(views_count: :desc)
    else                    reorder(created_at: :desc)
    end
  }

  # Seller "My Listings" tab filter. "expired" and "active" are refined so the
  # tabs cleanly partition: Active = live (not past expiry), Expired = active
  # but past its 30-day clock (the Renew bucket). Other values map to the enum.
  STATUS_FILTER_EXPIRED = "expired"
  scope :for_status_filter, lambda { |status|
    case status.to_s
    when STATUS_FILTER_EXPIRED then expired_active
    when "active"              then active.not_expired
    else where(status: status)
    end
  }
  # Buyer feed: active, not past its expiry, and not removed by an admin.
  scope :browsable,   -> { active.not_expired.not_removed.ordered }

  # Explicit per-user "Not interested" dismissal — excludes listings the given
  # user has hidden from their own feed. Guests (nil user) see everything.
  scope :not_hidden_for, ->(user) { user ? where.not(id: user.hidden_listings.select(:listing_id)) : all }

  # Similar listings rail: same category, browsable (never leaks draft/sold/expired/removed),
  # excluding the source listing itself, ordered by recency, capped at 8.
  scope :similar_to, lambda { |listing|
    browsable
      .where(category_id: listing.category_id)
      .where.not(id: listing.id)
      .limit(8)
  }

  # Exclude listings whose seller (a) has been blocked by +viewer+ or
  # (b) has blocked +viewer+.  Used by ListingPolicy::Scope so the filter
  # is applied to every list path without duplicating SQL.
  scope :excluding_blocked_pairs, lambda { |viewer|
    blocked_ids  = viewer.blocked_users.select(:id)
    blocking_ids = viewer.blocking_users.select(:id)
    where.not(user_id: blocked_ids).where.not(user_id: blocking_ids)
  }
  scope :price_at_least, ->(min) { where("price >= ?", min) }
  scope :price_at_most,  ->(max) { where("price <= ?", max) }
  scope :in_location,    ->(text) { where("LOWER(location) LIKE ?", "%#{text.to_s.downcase.strip}%") }
  scope :by_condition,   ->(c) { where(condition: c) }
  # Filter to listings whose seller has signed in within the last +days+ days.
  # Uses a JOIN on users — no extra SELECT per listing since the join is inlined
  # into the existing query chain; user/avatar eager-loading is unaffected.
  scope :seller_active_within, lambda { |days|
    joins(:user).where("users.last_sign_in_at >= ?", days.to_i.days.ago)
  }

  # Buyer "Deals" filter — listings that had a genuine price reduction
  # recorded in listing_price_histories within the last `days` days.
  # Uses a `where(id: subquery)` instead of `joins(:price_histories).distinct`
  # so the query stays a plain `listings.*` select — a JOIN + DISTINCT breaks
  # `ORDER BY` clauses that reference `listings` columns not in the SELECT
  # list (e.g. the Haversine `sort=nearest` ORDER BY), which Postgres rejects
  # with `PG::InvalidColumnReference: SELECT DISTINCT ... ORDER BY expressions
  # must appear in select list`. The subquery composes safely with any scope
  # or ORDER BY applied afterwards. Window defaults to PRICE_DROP_WINDOW (14
  # days) so the "Deals" filter matches exactly the listings that render the
  # price-drop badge.
  scope :with_recent_price_drop, lambda { |days = PRICE_DROP_WINDOW.in_days.to_i|
    where(id: ListingPriceHistory.reductions.recent(days).select(:listing_id))
  }

  # Listings whose coordinates fall within `km` kilometers of (lat, lng),
  # using the Haversine formula. LEAST/GREATEST clamp the acos argument to
  # [-1, 1] so floating-point drift can't raise a domain error.
  def self.within_radius(lat, lng, km)
    return all if lat.blank? || lng.blank? || km.blank?

    where.not(latitude: nil, longitude: nil)
         .where("#{haversine_distance_sql} <= ?", *haversine_binds(lat, lng), km.to_f)
  end

  # Orders listings by Haversine distance from (lat, lng), nearest first.
  # Reuses the exact same distance expression as `within_radius` so the two
  # compose cleanly (radius filter + nearest sort). Listings without
  # coordinates are excluded — they have no defined distance. Returns the
  # scope untouched (no reorder) when lat/lng are blank so callers can fall
  # back to another sort.
  def self.nearest_first(lat, lng)
    return all if lat.blank? || lng.blank?

    where.not(latitude: nil, longitude: nil)
         .reorder(Arel.sql(sanitize_sql_array([ "#{haversine_distance_sql} ASC", *haversine_binds(lat, lng) ])))
  end

  # The Haversine great-circle distance expression, parameterized with `?`
  # placeholders for (lat, lng, lat) — shared by `within_radius` (WHERE ... <=)
  # and `nearest_first` (ORDER BY ... ASC) so the math lives in one place.
  def self.haversine_distance_sql
    "#{EARTH_RADIUS_KM} * acos(LEAST(1, GREATEST(-1, " \
    "cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + " \
    "sin(radians(?)) * sin(radians(latitude)))))"
  end
  private_class_method :haversine_distance_sql

  def self.haversine_binds(lat, lng)
    [ lat.to_f, lng.to_f, lat.to_f ]
  end
  private_class_method :haversine_binds

  before_save :set_published_at, if: -> { active? && published_at.nil? }
  before_save :set_reserved_at,  if: -> { reserved? && reserved_at.nil? }
  before_save :set_sold_at,      if: -> { sold? && sold_at.nil? }

  # After a successful price update, record the change in listing_price_histories.
  # We use after_update (not before_save) so we only fire when the record is
  # already persisted and the write succeeded.
  after_update :record_price_history, if: :saved_change_to_price?

  # An active listing whose expiry has passed — hidden from the buyer feed,
  # shown to the seller with a "Renew" action.
  def expired?
    active? && expires_at.present? && expires_at.past?
  end

  # (Re)start the expiry clock — used on publish and on seller renew.
  def renew!
    update!(expires_at: LISTING_LIFESPAN.from_now)
  end

  # ── Admin take-down (soft remove) ────────────────────────────────────────────
  # Hides the listing from the public feed/detail page while keeping the record.
  def removed?
    removed_at.present?
  end

  def take_down!(reason: nil)
    update!(removed_at: Time.current, removed_reason: reason.presence)
  end

  def restore!
    update!(removed_at: nil, removed_reason: nil)
  end

  # Maximum number of words taken from a search query. Words beyond this cap
  # are silently discarded to prevent unbounded WHERE-chain construction.
  MAX_SEARCH_WORDS = 10

  def self.search(query)
    return all if query.blank?

    words = query.to_s.strip.split(/\s+/).first(MAX_SEARCH_WORDS)
    result = all

    words.each do |word|
      # Escape LIKE metacharacters so that literal "%" and "_" in a buyer's
      # query (e.g. "50%" or "model_x") are treated as plain characters, not
      # SQL wildcards.  We use backslash as the ESCAPE character (a single
      # backslash literal in SQL, written as '\' in the ESCAPE clause).
      escaped = word.downcase.gsub(/[\\%_]/) { |c| "\\#{c}" }
      term    = "%#{escaped}%"
      result  = result.where(
        "LOWER(title) LIKE ? ESCAPE '\\' OR LOWER(description) LIKE ? ESCAPE '\\'",
        term, term
      )
    end

    result
  end

  # Register a view for a listing, updating views_count according to these rules:
  #
  # 1. Owner viewing their own listing — never increment (seller analytics stay
  #    clean; the seller opening their own detail repeatedly won't bloat the
  #    count that buyers use as a trust signal).
  # 2. Signed-in non-owner — increment only on the FIRST ever view by that user
  #    (deduped via the unique index on listing_views). Repeat opens are a no-op.
  # 3. Guest (viewer nil) — increment once per request, but owner is always
  #    excluded (no per-guest identity exists yet, so we cannot deduplicate
  #    across requests; per-request single-increment is preserved).
  #
  # Returns true when views_count was incremented, false otherwise.
  def register_view!(viewer)
    return false if viewer && viewer.id == user_id

    if viewer
      _view, newly_created = ListingView.record!(viewer, self)
      increment!(:views_count) if newly_created
      newly_created
    else
      increment!(:views_count)
      true
    end
  end

  # ── Price-drop helpers (used by the serializer :list, :seller_list, :detailed views) ──
  PRICE_DROP_WINDOW = 14.days

  # The most recent price reduction within the last 14 days, or nil.
  #
  # When price_histories is already eager-loaded (e.g. from a list controller
  # that uses includes(:price_histories)), we filter in Ruby to avoid N+1
  # queries. When the association is not yet loaded we fall back to a targeted
  # SQL query.
  #
  # Memoized so that price_dropped_at and price_drop_percent (called
  # independently by the serializer) share a single lookup per record.
  def recent_price_drop
    return @recent_price_drop if defined?(@recent_price_drop)

    cutoff = PRICE_DROP_WINDOW.ago

    @recent_price_drop =
      if price_histories.loaded?
        price_histories
          .select { |h| h.new_price < h.old_price && h.changed_at >= cutoff }
          .max_by(&:changed_at)
      else
        price_histories
          .reductions
          .recent(14)
          .newest_first
          .first
      end
  end

  # ISO-8601 timestamp of the most recent price reduction, or nil.
  def price_dropped_at
    recent_price_drop&.changed_at&.iso8601
  end

  # Integer percent the price was reduced (e.g. 15 for 15% off), or nil.
  def price_drop_percent
    drop = recent_price_drop
    return nil unless drop

    pct = drop.drop_percent
    pct > 0 ? pct : nil
  end

  def thumbnail_url
    return nil unless images.attached?

    images.first.url
  rescue StandardError
    nil
  end

  def image_urls
    return [] unless images.attached?

    images.map(&:url)
  rescue StandardError
    []
  end

  # Images as {id, url} pairs. `id` is the blob's stable signed_id, which the
  # edit form echoes back in `removed_image_ids` to delete specific photos —
  # so editing keeps the rest of the gallery instead of replacing it.
  def image_attachments
    return [] unless images.attached?

    images.map { |a| { id: a.blob.signed_id, url: a.url } }
  rescue StandardError
    []
  end

  # ── Shareable deep-link URL ──────────────────────────────────────────────────
  # Returns an https share URL when PUBLIC_SHARE_BASE_URL env var is configured,
  # otherwise returns nil (the mobile app will fall back to a hatiwal:// deep link).
  # No hardcoded host in committed code — all infra config lives in .env / secrets.
  def self.share_url_for(listing)
    base = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    return nil if base.blank?

    "#{base.chomp('/')}/l/#{listing.id}"
  end

  private

  def record_price_history
    old_price, new_price = previous_changes[:price]
    return if old_price.nil? || new_price.nil?

    ListingPriceHistory.record_change!(
      listing:   self,
      old_price: old_price,
      new_price: new_price
    )
  end

  def set_published_at
    self.published_at = Time.current
  end

  def set_reserved_at
    self.reserved_at = Time.current
  end

  def set_sold_at
    self.sold_at = Time.current
  end
end
