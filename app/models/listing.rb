class Listing < ApplicationRecord
  # SF-B4 — raised when a correction is refused for a reason that is a product
  # decision rather than a validation failure: right now, exactly one case, a
  # sale that already has a review attached (see Transaction#correct!/#void!).
  # The controller turns it into a 422 carrying the machine-readable code
  # `sale_has_review`, so a 3-locale client can render its own copy instead of
  # showing an English sentence from the API.
  class CorrectionBlocked < StandardError; end

  belongs_to :user
  belongs_to :category
  has_many_attached :images
  has_many :saved_listings, dependent: :destroy
  has_many :listing_views, dependent: :destroy
  has_many :conversations, dependent: :nullify
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :price_histories, class_name: ListingPriceHistory.name, dependent: :destroy
  has_many :hidden_listings, dependent: :destroy
  # Named `sale_transactions` (not `transactions`) to avoid colliding with
  # ActiveRecord::Base#transaction (the DB-transaction method every model
  # inherits) — see TASK-TX01.
  has_many :sale_transactions, class_name: Transaction.name, dependent: :destroy

  enum :status, { draft: 0, active: 1, reserved: 2, sold: 3 }
  # Optional item condition. Keys avoid the reserved word `new` (would clash
  # with Listing.new); the mobile app maps them to "New / Like new / Good / Fair".
  enum :condition, { brand_new: 0, like_new: 1, good: 2, fair: 3 }, prefix: :condition

  validates :title, presence: true, length: { maximum: 150 }
  # The `price` column is decimal(12, 2), so any value above 9_999_999_999.99
  # overflows in Postgres and raises ActiveRecord::RangeError *after* validation
  # has already passed. That surfaces to the mobile app as a 500 with no field
  # errors, so the seller sees the publish fail with nothing telling them why —
  # exactly the "it failed but I don't know from where" report. Bounding it here
  # turns that into an ordinary 422 carrying a message on :price.
  MAX_PRICE = 9_999_999_999.99
  validates :price, presence: true,
                    numericality: { greater_than: 0, less_than_or_equal_to: MAX_PRICE }
  # Multi-quantity listings (docs/SPIKE_LISTING_QUANTITY.md, Tier 1). Defaults to
  # 1 so nothing existing changes; the 999 ceiling is a sanity bound, not a
  # business rule — this is a local marketplace, not a warehouse.
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 999 }
  validates :sold_units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # SF-B6 — a seller editing `quantity` DOWN below what they have ALREADY sold
  # used to reach the DB CHECK constraint `listings_sold_units_within_quantity`
  # and come back as an uncaught ActiveRecord::CheckViolation: a 500 with an
  # empty body, so the seller taps Save, it fails, and the app can only show its
  # generic "server error". Exactly the failure class MAX_PRICE was added to
  # prevent (see its note above), bounded the same way — an ordinary 422 with a
  # message on :quantity. The CHECK constraint STAYS as the backstop for
  # everything that bypasses validation (update_column, raw SQL, Administrate).
  #
  # The copy names the way out, because since SF-B4 there IS one:
  # DELETE /api/v1/my/transactions/:id undoes a recorded sale and puts its units
  # back, which lowers `sold_units` and lets the same edit through.
  QUANTITY_BELOW_SOLD_UNITS       = :below_sold_units
  # Wire code the client maps to its own ps/fa/en copy — the `errors` array is
  # English Rails prose, and this app must never show an untranslated string to a
  # Pashto or Dari seller. Mirrors SF-B4's `sale_has_review`.
  QUANTITY_BELOW_SOLD_UNITS_CODE  = "quantity_below_sold_units".freeze
  validate :quantity_covers_sold_units

  # SF-B8 — the sibling rule one floor over: `quantity` may never fall below the
  # units currently ON HOLD for a buyer either.
  #
  # SF-B6 covered units already SOLD; nothing covered an open hold. So a listing
  # with 15 units and 10 held for a buyer accepted an edit down to `quantity: 2`,
  # and the buyer-facing held pill (SF-M4) then rendered "2 available · 10 held"
  # — arithmetic nonsense, on a stranger's screen, in the one place this app has
  # to be believable.
  #
  # THE EDIT IS REFUSED, the hold is NOT silently shrunk. Both were on the table;
  # refusing won for two reasons:
  #
  #   * it mirrors `quantity_covers_sold_units` sitting immediately above, so a
  #     seller meets ONE rule ("quantity covers what you have committed") instead
  #     of two contradictory ones (sold units block the edit, held units quietly
  #     rewrite someone's reservation);
  #   * a hold is a promise between two people who have already agreed to meet in
  #     person. There is no payment in this marketplace to arbitrate a broken one
  #     — trust IS the product — so a seller shrinking a reservation must do it
  #     deliberately, not discover it happened.
  #
  # The way out is named in the copy and is a real endpoint:
  # PUT /api/v1/my/listings/:id/activate releases the hold (it destroys the open
  # Transaction), after which the same down-edit goes through.
  QUANTITY_BELOW_HELD_UNITS       = :below_held_units
  # Wire code, same contract and same reason as QUANTITY_BELOW_SOLD_UNITS_CODE
  # above: the `errors` array is raw English Rails prose and this app ships en +
  # ps + fa, so the client localizes off the code and never echoes the string.
  QUANTITY_BELOW_HELD_UNITS_CODE  = "quantity_below_held_units".freeze
  validate :quantity_covers_held_units
  CURRENCIES = %w[AFN USD EUR].freeze
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :category, presence: true

  # Photo limits. Both clients cap their picker at 8 photos (mobile
  # PhotosSection MAX_DEFAULT, web listing-form MAX_PHOTOS); this enforces the
  # same ceiling where a client cannot bypass it, plus a per-file size and type
  # check. Nothing validated `images` before, so `listing[images][]` accepted
  # any file of any size, any number of times.
  MAX_IMAGES     = 8
  MAX_IMAGE_SIZE = 10.megabytes
  validates :images,
            attached_file: {
              types:     AttachedFileValidator::IMAGE_TYPES,
              max_size:  MAX_IMAGE_SIZE,
              max_count: MAX_IMAGES
            }

  # `description` is a text column and was entirely unbounded, so a client could
  # POST a megabyte of prose per listing. 3 000 characters is far longer than any
  # real item description needs (the title cap is 150, a chat message 1 000).
  MAX_DESCRIPTION_LENGTH = 3_000
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }

  # A listing must carry at least one photo before it goes live. This is a
  # photo-first marketplace: a photoless card renders as the grey "no photo" box,
  # which reads to buyers as broken or fake.
  #
  # Deliberately scoped to the draft -> active transition ONLY. A listing created
  # directly as active (seeds, Administrate) and a reserved listing being
  # reactivated after a deal fell through are both left alone, so nothing that is
  # ALREADY published can be stranded — unable to be edited, renewed or marked
  # sold — by a rule introduced after it was created. Drafts stay saveable with
  # no photos, which is what the "Save draft" button needs.
  validate :photo_required_to_publish, if: :publishing?

  # A listing's coordinate must be a real coordinate.
  #
  # SavedSearch has validated its latitude range since it was written; Listing
  # never did, so `latitude: 91` was accepted and persisted through
  # POST /api/v1/my/listings (verified: 201, and lat=91.0 in the database). That
  # is not a country restriction — a location OUTSIDE Afghanistan is deliberately
  # allowed, and Paris and Sydney both save fine — it is the difference between
  # "anywhere on Earth" and "off the Earth".
  #
  # It matters downstream: `distance_from` runs a haversine over these columns for
  # nearest-first sort and radius filters, and a marker at 91°N cannot be drawn.
  validates :latitude,
            numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 },
            allow_nil: true
  validates :longitude,
            numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 },
            allow_nil: true

  EARTH_RADIUS_KM = 6371
  # How long a published listing stays in the buyer feed before it expires.
  LISTING_LIFESPAN = 30.days

  # Valid sort keys accepted by the API. "nearest" additionally requires
  # latitude/longitude — the controller applies `nearest_first` for it and
  # falls back to the default (newest) ordering when coordinates are absent.
  SORT_KEYS = %w[newest oldest price_asc price_desc most_viewed nearest].freeze

  scope :active,      -> { where(status: :active) }
  # SF-B1 — "live" is the market-visible pair. A `reserved` listing has NOT left
  # the market: on a single item it means "someone is first in line", on a batch
  # it means "some units are held" (the status is not even flipped there). Before
  # this scope existed, `browsable` was `active`-only, so reserving a bike made it
  # vanish from search with nothing telling the seller why — the "my listing
  # disappeared" report this widen exists to fix (docs/SELL_FLOW_AUDIT.md §7).
  #
  # `sold`, `draft` and admin-removed listings are the genuinely-unavailable set
  # and stay out.
  scope :live,        -> { where(status: [ :active, :reserved ]) }
  scope :ordered,     -> { order(created_at: :desc) }
  # Filtering by a category includes everything filed under its subcategories:
  # the create-listing picker lets a seller file an item under
  # "Electronics > Phones", and that item is still an Electronics listing.
  # Expressed as a subquery so it stays one round-trip and composes with the
  # rest of the browse scope chain.
  scope :by_category, ->(id) { where(category_id: Category.self_and_children(id).select(:id)) }
  scope :by_seller,   ->(id) { where(user_id: id) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :not_removed, -> { where(removed_at: nil) }
  # A LIVE listing (active or reserved) whose 30-day clock has run out — the
  # seller's "Expired"/Renew bucket. Widened with `live` alongside `expired?`
  # (SF-B1): a reserved listing that can expire must also be able to land in the
  # tab that offers Renew, or it would drop out of `browsable` (`not_expired`)
  # and appear in NO seller tab at all. Name kept for its callers.
  scope :expired_active, -> { live.where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }

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
  # tabs cleanly partition: Active = live (not past expiry), Expired = live but
  # past its 30-day clock (the Renew bucket). Other values map to the enum.
  #
  # SF-B1: the "active" tab is `live`, so a held listing stays in the tab the
  # seller already had it in instead of moving to a separate "Reserved" tab the
  # clients are dropping. An explicit `?status=reserved` still returns exactly
  # the reserved rows via the `else` branch — nothing that asks for the raw enum
  # loses the ability to.
  STATUS_FILTER_EXPIRED = "expired"
  scope :for_status_filter, lambda { |status|
    case status.to_s
    when STATUS_FILTER_EXPIRED then expired_active
    when "active"              then live.not_expired
    else where(status: status)
    end
  }
  # Buyer feed: live (active OR reserved), not past its expiry, and not removed
  # by an admin. THE load-bearing line of SF-B1 — the feed, search, category
  # counts, the similar-listings rail and recently-viewed all compose on top of
  # this one scope, so widening it here widens all of them at once.
  scope :browsable,   -> { live.not_expired.not_removed.ordered }

  # Explicit per-user "Not interested" dismissal — excludes listings the given
  # user has hidden from their own feed. Guests (nil user) see everything.
  scope :not_hidden_for, ->(user) { user ? where.not(id: user.hidden_listings.select(:listing_id)) : all }

  # Similar listings rail: same category, browsable (never leaks draft/sold/expired/removed),
  # excluding the source listing itself, ordered by recency, capped at 8.
  #
  # Uses +by_category+ (self_and_children), not a bare category_id match: a seller
  # who files an item on a PARENT category ("Electronics") would otherwise get an
  # empty rail even when the children below it are full of stock. Filed on a leaf
  # this is identical to a plain equality check, so the rail can only get wider.
  scope :similar_to, lambda { |listing|
    browsable
      .by_category(listing.category_id)
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

  # SF-B6 — a plain `PUT /my/listings/:id` that changes `quantity` must reconcile
  # the listing's status, exactly as a sale correction already does (SF-B4).
  #
  # Both directions were broken because nothing reconciled after a quantity edit:
  #
  #   UP   15 of 15 sold, seller edits quantity to 20 -> stayed `sold` with 5
  #        unsold units: out of `browsable` (buyers cannot see it) AND out of
  #        `ListingPolicy#sold?` (which needs `live?`, so the seller cannot sell
  #        them either). Stock stranded with no in-app recovery.
  #   DOWN a live listing whose quantity drops onto `sold_units` stayed `active`
  #        with nothing left to sell.
  #
  # `after_update` rather than `before_save` because `reconcile_sold_status!` is
  # the SF-B4 method reused verbatim, and it persists with `update!` — the same
  # shape, for the same reason, as `record_price_history` directly above.
  #
  # Registered AFTER `record_price_history` deliberately: the nested `update!`
  # inside the reconcile REPLACES `saved_changes` with the nested save's, so
  # running first would hide a price change from the history recorder on an edit
  # that changed price and quantity together (guarded by its own spec).
  #
  # No recursion: the nested save touches `status`/`sold_at`/`expires_at`, never
  # `quantity`, so this guard is false the second time through.
  after_update :reconcile_status_after_quantity_change, if: :saved_change_to_quantity?

  # Still on the market: active, or reserved-but-not-gone (SF-B1). The predicate
  # form of the `live` scope — used by ListingPolicy#start_conversation?,
  # Conversations::StartService and SavedListing#price_dropped?, all of which
  # asked `active?` and so treated a held listing as a dead end.
  def live?
    active? || reserved?
  end

  # A live listing whose expiry has passed — hidden from the buyer feed, shown
  # to the seller with a "Renew" action.
  #
  # SF-B1 widened this from `active?` to `live?`: a reserved listing used to
  # never expire, so it sat live forever. Now that reserved listings are
  # browsable that would be a listing in the feed with an expiry the feed itself
  # ignores.
  def expired?
    live? && expires_at.present? && expires_at.past?
  end

  # (Re)start the expiry clock — used on publish and on seller renew.
  def renew!
    update!(expires_at: LISTING_LIFESPAN.from_now)
  end

  # draft -> active. Flips the status and starts the expiry clock in ONE write so
  # `photo_required_to_publish` can veto the whole transition: returns false with
  # the errors left on the record, which the controller renders as a 422. (The
  # controller used to call `active!` + `renew!`, two bang writes that would have
  # raised RecordInvalid — a 500 — the moment publishing could fail.)
  def publish
    self.status     = :active
    self.expires_at = LISTING_LIFESPAN.from_now
    save
  end

  # ── Transactions (TASK-TX01) ─────────────────────────────────────────────────
  # The currently open (reserved, not yet sold) Transaction for this listing,
  # or nil. A listing has at most one open transaction at a time (enforced by
  # a partial unique DB index on transactions.listing_id).
  def open_transaction
    sale_transactions.reserved.order(created_at: :desc).first
  end

  # The same row as #open_transaction, read from an ALREADY-EAGER-LOADED
  # association when there is one.
  #
  # `sale_transactions.reserved` always hits the database — an association's
  # scope ignores its loaded target — so calling #open_transaction from a
  # serializer field would fire one query per row and reintroduce the exact N+1
  # `current_sale` was written to avoid (see its own note below, and the guard
  # spec "issues a constant number of queries regardless of how many rows have a
  # Transaction"). The mutation paths (#reserve_with_buyer!,
  # #cancel_open_transaction!) deliberately keep using #open_transaction: they
  # must never act on a possibly-stale in-memory copy.
  def open_sale
    return open_transaction unless sale_transactions.loaded?

    sale_transactions.select(&:reserved?).max_by(&:created_at)
  end

  # SF-B2 — how many units are currently HELD for a buyer, as a plain integer.
  #
  # PUBLIC-SAFE BY CONSTRUCTION: a count, never an identity. This is what powers
  # the buyer-facing "13 available · 2 held" clause, so it ships on the base
  # serializer fields (every view, guests included). The buyer's NAME for a held
  # listing stays owner-only, on the existing `sale` field — do not add anything
  # here that could identify them.
  #
  # Advisory, not an inventory reservation: held units are NOT subtracted from
  # `available_units` (docs/SELL_FLOW_REDESIGN.md §3.6). A real per-unit hold
  # would need expiry/leak machinery this marketplace deliberately does not have.
  def held_units
    (open_sale&.quantity).to_i
  end

  # SF-B5 — how many SOLD entries this listing's ledger holds (not units: a buyer
  # taking 3 of 15 is ONE sale). Same loaded-vs-query guard as everything else
  # that reads `sale_transactions` from a serializer field.
  def sales_count
    if sale_transactions.loaded?
      sale_transactions.count(&:sold?)
    else
      sale_transactions.sold.count
    end
  end

  # ── Multi-quantity (docs/SPIKE_LISTING_QUANTITY.md, Tier 1) ─────────────────

  # Units still for sale. The number a buyer is shown, and the ceiling on what a
  # seller can mark sold in one go.
  def available_units
    [ quantity - sold_units, 0 ].max
  end

  # True only for listings the seller explicitly said they had several of. Every
  # client uses this to decide whether to render ANY quantity UI at all, so a
  # single-unit listing looks exactly as it does today — the governing rule of
  # the spike's §0c.
  def multi_unit?
    quantity > 1
  end

  # Record `units` sold and return whether that emptied the listing.
  #
  # `with_lock` is hygiene rather than the load-bearing protection the spike
  # first assumed: only the OWNER can mark units sold (the endpoint is
  # PUT /my/listings/:id/sold, Pundit-authorized), so there is no buyer race to
  # lose — just a seller double-tapping. The DB CHECK constraint is the thing
  # that genuinely cannot be bypassed.
  def record_units_sold!(units)
    units = units.to_i
    raise ArgumentError, "units must be positive" if units < 1

    with_lock do
      # Never oversell. A seller marking 5 sold on a listing with 3 left sells 3;
      # clamping beats raising here because the sale physically happened and
      # refusing to record it would lose the ledger entry.
      taken = [ units, available_units ].min
      return false if taken.zero?

      update!(sold_units: sold_units + taken)
      # SF-B9 — the units that just left the shelf may have been the same units
      # an open hold was still claiming. Bring the hold back inside what is
      # actually left; see #shrink_open_hold_to_available_units!.
      shrink_open_hold_to_available_units!
      available_units.zero?
    end
  end

  # TASK-R418 — the buyer identified for the CURRENT reservation/sale of this
  # listing, or nil when the listing has never had a buyer identified via the
  # buyer picker: draft/active listings, or a legacy buyer-less reserve/sold.
  # Used by ListingSerializer's owner-only `sale` field (:seller_list /
  # :owner_detailed views) — NEVER surfaced on the public :list / :detailed
  # views.
  #
  # CR fix (CYCLE-4, HIGH): a listing can accumulate MULTIPLE Transaction rows
  # over its lifetime (a reservation that fell through and was re-reserved,
  # or an admin flipping `status` directly via Administrate — see
  # Transaction#bump_trust_counters!'s own admin-bypass note) — so "most
  # recently CREATED" is not the same thing as "the transaction whose status
  # actually matches where this listing is right now". Filtering by status
  # first (sold when the listing is sold, reserved when it's reserved) means
  # a mismatched/stale row is never surfaced as this listing's sale — we show
  # nothing rather than the wrong buyer.
  #
  # Mirrors the loaded-vs-query guard used by `recent_price_drop` above: when
  # the controller eager-loads `sale_transactions`, we filter/sort the
  # already-loaded array in Ruby instead of firing a fresh `.where(...)`
  # query per row (an association's scope always hits the DB, ignoring the
  # loaded target), which would reintroduce an N+1 across the seller feed.
  # SF-B2 — the `reserved? || sold?` gate is gone. It made this method blind to
  # the single case the multi-quantity feature created: a MULTI-UNIT listing
  # whose status deliberately stays `active` while units are held for a buyer
  # (My::ListingsController#reserve, "a batch does not leave the market because
  # one unit is held"). `current_sale` returned nil there, so the seller's own
  # listing card showed no buyer for a hold they had just placed.
  #
  # Now: a sold listing surfaces its latest SOLD row; anything else surfaces the
  # open hold, if any. That covers single-item `reserved?` and multi-item
  # `active?`-with-a-hold through one expression instead of two special cases.
  def current_sale
    # A SOLD listing shows the sale that completed it — never a hold row that
    # happened to survive (a batch can be sold out to one buyer while an older
    # hold for someone else is still open).
    return latest_sold_sale if sold?

    # Otherwise: the hold in progress if there is one, else the most recent
    # completed sale. That last fallback is what makes a PARTIALLY-sold live
    # batch show its latest buyer ("sold 3 to Zahra") next to `sales_count`'s
    # "+2 more · View all sales" — without it the card vanished the moment a
    # correction re-opened a sold-out listing, and a partially-sold batch showed
    # no buyer at all even though the ledger held several (audit §5, Gap D).
    open_sale || latest_sold_sale
  end

  # Create or advance the Transaction when the seller reserves this listing
  # for a specific buyer. Returns nil (no-op) when buyer_id is blank — the
  # legacy bare `PUT .../reserve` call never touches the transactions table.
  # SF-B2 adds the optional `quantity`. Without it a reservation was always
  # `quantity: 1` (the column default) regardless of batch size, so "N held for
  # Ahmad" could only ever say "1 held" — the number was a lie on any batch. The
  # clamp mirrors `sold_with_buyer!` field-for-field: a single-item listing
  # ignores the param entirely (there is exactly one unit to hold), and a stale
  # client cannot hold more units than exist.
  def reserve_with_buyer!(buyer_id:, final_price: nil, quantity: nil)
    return nil if buyer_id.blank?

    units = multi_unit? ? (quantity.presence || 1).to_i.clamp(1, [ available_units, 1 ].max) : 1

    existing = open_transaction
    if existing
      existing.update!(buyer_id: buyer_id, final_price: final_price.presence || price, quantity: units)
      existing
    else
      sale_transactions.create!(
        seller_id: user_id,
        buyer_id: buyer_id,
        final_price: final_price.presence || price,
        currency: currency,
        status: :reserved,
        quantity: units
      )
    end
  end

  # Create or advance the Transaction to sold when the seller marks this
  # listing as sold for a specific buyer. When a reserved Transaction already
  # exists it is advanced (reserved → sold); otherwise a sold Transaction is
  # created directly (selling straight from active, skipping reserve).
  # Returns nil (no-op) when buyer_id is blank AND there is no existing
  # reservation to close out — the legacy bare `PUT .../sold` call never
  # touches the transactions table for a listing that was never reserved
  # through the buyer picker.
  #
  # `clear_buyer: true` (TASK-TX02 review fix, MAJOR) is the WIRE-DISTINGUISHABLE
  # signal that the seller explicitly tapped BuyerPickerSheet's "Someone else /
  # skip" option — as opposed to a true legacy client that never sends any
  # buyer info at all. On the wire, both cases look identical (`buyer_id`
  # simply absent) unless something else marks the explicit case — so
  # `clear_buyer` cancels any open reservation outright instead of silently
  # re-attributing it to whoever was previously reserved. Without this
  # distinction, an innocent previously-reserved buyer could be credited with
  # a purchase they did not make the moment the seller says "no, not them."
  #
  # The close-out of an EXISTING reservation (the pre-TX02-review-fix, still
  # legitimate "I already told you who" case) is decided by
  # `#hold_closed_by_sale` — NOT by the listing's own status. SF-B9 moved that
  # line; read its note for why the `reserved?` gate it replaced had stopped
  # being true. TASK-TX02's protection is unchanged and is now stated directly:
  # a hold belonging to a DIFFERENT buyer is never re-attributed to this sale,
  # and a buyer-less sale still only closes out a listing that is genuinely
  # `reserved` right now — see the reproduction this guards in
  # spec/requests/api/v1/my/listings_spec.rb.
  def sold_with_buyer!(buyer_id:, final_price: nil, clear_buyer: false, quantity: nil)
    # SF-B3 — every `sold` call now leaves EXACTLY ONE sold Transaction. There is
    # no `return nil` branch left.
    #
    # Two paths used to record nothing: the explicit "Someone else / skip"
    # (`clear_buyer: true`) and the bare legacy call that carries no buyer info at
    # all. Both moved `sold_units` while the ledger stayed silent, so the seller
    # could never see the sale again and SF-B4's correction endpoint had nothing
    # to point at. They are the SAME fact — a sale happened, no counterparty was
    # recorded — so they now produce the same row, and
    # Transaction#bump_trust_counters! counts the seller's sale once, like every
    # other sale. That is what let `bump_seller_sold_count_for_legacy_sale!` be
    # deleted rather than merely bypassed.
    #
    # `cancel_open_transaction!` on the clear_buyer branch keeps its original
    # reason: a specific reserved buyer falling through is a SEPARATE fact from
    # this sale, and must never be silently re-attributed to whoever happened to
    # be holding it (TASK-TX02 review fix, MAJOR).
    if clear_buyer
      cancel_open_transaction!
      return create_sold_sale!(buyer_id: nil, final_price: final_price, units: units_for_sale(quantity))
    end

    existing = hold_closed_by_sale(buyer_id)
    if existing
      # Closing out an existing hold. The units already HELD are the sale unless
      # the seller says otherwise — before SF-B2 gave a hold a real quantity
      # there was no held number to honour, so this defaulted to a guess.
      #
      # `mark_sold!` itself defaults a blank buyer_id back to the transaction's
      # own buyer_id (see Transaction#mark_sold!), so passing it straight through
      # is safe whether or not this call identified one.
      existing.update!(quantity: units_for_sale(quantity, default: existing.quantity)) if multi_unit?
      existing.mark_sold!(final_price: final_price, buyer_id: buyer_id)
      return existing
    end

    # `buyer_id.presence` is what makes the bare legacy call a buyer-less sale
    # rather than a validation error.
    create_sold_sale!(
      buyer_id: buyer_id.presence, final_price: final_price, units: units_for_sale(quantity)
    )
  end

  # Cancel any still-open (reserved) Transaction for this listing — a no-op
  # when none exists. Called from `activate` (reserved → active, "the deal
  # fell through") and from `sold_with_buyer!`'s `clear_buyer` branch above,
  # so a stale reserved row can never survive to be silently closed out
  # against the wrong buyer by a later buyer-less `sold` call (TASK-TX02
  # review fix, MAJOR).
  def cancel_open_transaction!
    open_transaction&.destroy!
  end

  # ── SF-B4: undo & edit a recorded sale ──────────────────────────────────────
  #
  # The hole this closes (docs/SELL_FLOW_AUDIT.md §4): a seller who tapped "sold
  # 5" on a batch of 15 instead of "sold 1" had permanently lost 4 units of
  # stock. `record_units_sold!` only ever ADDS, the counters were increment-only,
  # and a sold-out listing was terminal — so there was no path down anywhere in
  # the stack, and repair meant a human running a rake task.
  #
  # ONE method does both the toast's "Undo" and the Sales screen's editable row.
  # There is no separate "correction form" concept: `quantity: 0` (or any
  # non-positive number) means "this sale did not happen", anything else means
  # "it was for this many".
  #
  # The listing's own status is reconciled as a SIDE EFFECT of fixing the ledger,
  # never as a separate action a seller has to find: dropping below full stock
  # re-opens a `sold` listing, and reaching full stock retires an `active` one. A
  # single-item listing's only possible correction is voiding its one sale (its
  # quantity cannot go below 1 without voiding) — same code path, no special case.
  #
  # `with_lock` here is load-bearing in a way it is not in `record_units_sold!`:
  # this method READS `sold_units`, computes from it and writes it back, so two
  # concurrent corrections could otherwise lose one of the two adjustments. The
  # transaction row is locked too, in a fixed order (listing then transaction) so
  # two corrections on the same listing cannot deadlock each other.
  def correct_sold_transaction!(transaction:, quantity: nil, buyer_id: nil, clear_buyer: false, final_price: nil)
    raise ArgumentError, "transaction does not belong to this listing" unless transaction.listing_id == id
    raise ArgumentError, "only a sold transaction can be corrected" unless transaction.sold?

    # `total_units` and not `quantity`: the keyword argument SHADOWS the column
    # reader inside this method, and reading the seller's requested number where
    # the listing's total was meant is exactly the kind of silent mistake that
    # would corrupt stock. Named apart so it cannot happen.
    total_units = self.quantity
    voiding     = quantity.present? && quantity.to_i <= 0

    with_lock do
      transaction.lock!
      old_units = transaction.quantity

      if voiding
        transaction.void!
        new_sold_units = [ sold_units - old_units, 0 ].max
      else
        new_units = quantity.presence&.to_i || old_units
        # What this sale is allowed to grow to: everything not accounted for by
        # the OTHER sales of this listing.
        capacity = total_units - (sold_units - old_units)
        raise_capacity_error!(transaction, new_units, capacity) if new_units < 1 || new_units > capacity

        transaction.correct!(
          quantity: new_units, buyer_id: buyer_id, clear_buyer: clear_buyer, final_price: final_price
        )
        new_sold_units = [ sold_units - old_units + new_units, 0 ].max
      end

      update!(sold_units: new_sold_units)
      reconcile_sold_status!(new_sold_units, total_units)
    end

    reload
  end

  # SF-B3 removed `bump_seller_sold_count_for_legacy_sale!`.
  #
  # It existed for exactly one reason: an outside-buyer ("Someone else / skip")
  # sale created NO Transaction, so nothing else ever bumped the seller's
  # sold_count for it, and the controller had to do it by hand. That sale now
  # always creates a sold Transaction, and Transaction#bump_trust_counters!
  # counts it like every other sale — so keeping the manual bump would have
  # counted every outside-buyer sale TWICE. Deleted here and at its call site in
  # My::ListingsController#sold together, deliberately, as one change.
  #
  # The genuinely buyer-less legacy path that remains (a bare `PUT .../sold` with
  # no buyer_id and no clear_buyer, on a listing that was never reserved) still
  # creates no Transaction and still bumps nothing — unchanged, and correct: no
  # counterparty was ever asserted, so there is no confirmed sale to count.

  # SF-B6 — the machine-readable code for the validation errors currently on this
  # record, or nil. Lives here rather than in the controller so the controller
  # stays a two-liner and the code/validation pair can never drift apart.
  #
  # Only the quantity-floor failures get one: they are the edit errors a seller is
  # expected to ACT on (undo a sale, release a hold, or raise the number), so the
  # client has to render them inline under the field in the seller's own language
  # instead of echoing the English `errors` string.
  #
  # SF-B8 added the second code. The two can never BOTH be present: the floors
  # report exclusively — whichever is higher raises the error and the other stays
  # silent (see `hold_sets_quantity_floor?`) — so this is an ordered list of
  # mutually exclusive cases, not a tiebreak that runs in practice.
  #
  # It is still written as a precedence, deliberately, so a future third rule
  # cannot make this method return whichever code happens to be first in the
  # errors array: units-already-sold wins, because it is the floor a seller cannot
  # lower by releasing anything — undoing a completed sale needs SF-B4's
  # correction endpoint, while a hold is released with one tap on `activate`.
  def error_code
    return QUANTITY_BELOW_SOLD_UNITS_CODE if errors.where(:quantity, QUANTITY_BELOW_SOLD_UNITS).any?
    return QUANTITY_BELOW_HELD_UNITS_CODE if errors.where(:quantity, QUANTITY_BELOW_HELD_UNITS).any?

    nil
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

  # Grid-card thumbnail dimensions. The Bazaar/Saved/My-Listings grids show a
  # small 2-column card, so serving the full-size original (often several MB)
  # made every card take many seconds to download. A resized variant keeps the
  # payload tiny.
  THUMBNAIL_RESIZE_LIMIT = [ 600, 600 ].freeze

  def thumbnail_url
    return nil unless images.attached?

    image = images.first
    # Non-image blobs (e.g. a stray PDF) aren't variable — fall back to the original.
    return image.url unless image.blob.variable?

    # Return a LAZY representation URL rather than calling `.processed.url`: the
    # variant is generated on the client's first request to this URL (then
    # cached), NOT synchronously during the list query. This keeps the index a
    # constant number of queries (no N+1 from per-listing variant processing)
    # while still delivering the small resized image to the app.
    variant = image.variant(resize_to_limit: THUMBNAIL_RESIZE_LIMIT)
    Rails.application.routes.url_helpers.rails_representation_url(
      variant, **(ActiveStorage::Current.url_options || {})
    )
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

  # SF-B9 — the open hold that THIS `sold` call closes out, or nil.
  #
  # It used to be `reserved? ? open_transaction : nil`. That read the LISTING'S
  # STATUS as a proxy for "is a hold in progress", which was true when placing a
  # hold always flipped the status — and stopped being true the day SF-B2 made a
  # multi-unit batch deliberately stay `active` while units are held ("a batch
  # does not leave the market because one unit is held"). From then on `existing`
  # was ALWAYS nil for a batch, so selling held units to the very buyer holding
  # them left the hold open beside the new sale: two rows, and a buyer reading
  # "5 available · 10 held" for ten units already sold to them (measured, not
  # theorised — card SF-B9). The same phantom hold then set SF-B8's quantity
  # floor, so it refused legitimate down-edits too.
  #
  # The question the gate should have been asking all along is not "where is the
  # listing" but "is there an open hold FOR THIS BUYER". Both cases below are
  # that question; neither reads `status` as evidence of a hold:
  #
  #   * the seller named the person the units are held for -> this sale IS that
  #     hold completing, whatever the listing's status. Covers single-item
  #     (`reserved`) and batch (`active`) through one expression.
  #   * a buyer-LESS call (a true legacy client, which sends no buyer info at
  #     all) on a listing that is genuinely `reserved` right now -> closes out
  #     using the buyer already recorded on the hold. TASK-TX02's case, verbatim,
  #     including its `reserved?` requirement: a hold that has fallen through
  #     must never be resurrected by a later buyer-less sale.
  #
  # And TASK-TX02's protection, now stated rather than implied: a hold belonging
  # to a DIFFERENT buyer is NOT closed out against this sale. Someone who never
  # bought the item cannot be credited with buying it, and the sale keeps its own
  # row instead of quietly repurposing theirs. (The explicit "Someone else /
  # skip" tap has always said so with `clear_buyer`; this makes the same true of
  # naming a different buyer outright.) What happens to that other buyer's hold
  # afterwards is decided by stock, not by this method — see
  # #shrink_open_hold_to_available_units!.
  def hold_closed_by_sale(buyer_id)
    hold = open_transaction
    return nil if hold.nil?
    return hold if buyer_id.present? && hold.buyer_id.present? && hold.buyer_id == buyer_id.to_i
    return hold if buyer_id.blank? && reserved?

    nil
  end

  # SF-B9 — keep an advisory hold inside the stock that actually remains.
  #
  # A hold is deliberately NOT an inventory reservation: `held_units` is never
  # subtracted from `available_units` (docs/SELL_FLOW_REDESIGN.md §3.6), so a
  # seller CAN sell units another buyer is holding — nothing set them aside. What
  # they must not be able to do is leave a hold claiming more units than the
  # listing has left, which renders on a stranger's screen as "0 available ·
  # 1 held" — the exact arithmetic nonsense SF-B8 exists to keep off it, reached
  # here through an ordinary sale rather than an edit.
  #
  # So the hold is narrowed to what survived the sale, and destroyed when
  # nothing did. Only ever narrowed, never widened.
  #
  # This is deliberately NOT the call SF-B8 makes. There a seller LOWERING
  # `quantity` is refused rather than having a hold silently shrunk, because an
  # edit is a choice they can revise and a hold is a promise between two people
  # who agreed to meet. A sale is not a choice — it already happened in person,
  # which is why `record_units_sold!` clamps instead of raising ("refusing to
  # record it would lose the ledger entry"). A hold on units that no longer
  # exist cannot be honoured by anybody; saying so is the honest option left.
  #
  # Destroying a still-`reserved` row touches no trust counter — only a `sold`
  # row ever bumped one (Transaction#void! reasons the same way).
  #
  # `update_columns` and not `update!`, which is load-bearing rather than a
  # shortcut — measured, not assumed. Transaction validates
  # `buyer_is_conversation_participant`, and a Conversation is HARD-destroyed
  # once BOTH parties delete the thread (Conversation#delete_for!). So a hold
  # whose thread is gone cannot be saved at all, and an `update!` here made the
  # WHOLE SALE fail: 422 "Buyer must be a participant in a conversation on this
  # listing", naming a rule about a third party's deleted chat, rolled back
  # inside My::ListingsController#sold's DB transaction — a seller unable to
  # record a real sale because of a hold they are not even selling to.
  #
  # A narrowing write of ONE column must not be refused by a validation about an
  # attribute it does not touch and an inconsistency that predates it. Same call
  # `record_units_sold!` makes one floor up: the sale already happened, so it is
  # recorded, and `transactions_quantity_positive` (quantity >= 1) is the DB
  # backstop that cannot be edited away — honoured here by destroying the row
  # rather than writing a zero. `updated_at` is moved by hand since
  # `update_columns` will not.
  def shrink_open_hold_to_available_units!
    hold = open_transaction
    return if hold.nil? || hold.quantity <= available_units
    return hold.destroy! if available_units.zero?

    hold.update_columns(quantity: available_units, updated_at: Time.current)
  end

  # How many units one `sold` call covers.
  #
  # Defaults to ONE unit of a batch, not the whole shelf — the seller's number
  # when they give one, otherwise the conservative reading of "I sold it". This
  # matches the default My::ListingsController#sold has documented since the
  # device report it came from (50 in stock, one sale, listing retired reading
  # "0 of 50 left"): in a marketplace with no payments, the destructive outcome
  # must be the one you ask for explicitly, never the silent one.
  #
  # A single-item listing is unaffected — its `available_units` IS 1, so both
  # halves of the ternary are the same number.
  #
  # Clamped so a stale client cannot oversell; the DB CHECK constraint
  # (`listings_sold_units_within_quantity`) is the backstop that cannot be edited
  # away.
  # `default:` lets the caller override the fallback — used when closing out a
  # hold, where the units already held are the better default than a guess.
  def units_for_sale(quantity, default: nil)
    fallback = default || (multi_unit? ? 1 : available_units)
    (quantity.presence || fallback).to_i.clamp(1, [ available_units, 1 ].max)
  end

  # Re-open a listing that went sold-out by mistake, or retire one whose
  # correction has just emptied it. `sold_at` is cleared on the way back out so
  # the seller's card does not keep claiming a sale date for a listing that is
  # live again.
  def reconcile_sold_status!(new_sold_units, total_units)
    if sold? && new_sold_units < total_units
      update!({ status: :active, sold_at: nil }.merge(refreshed_expiry))
    elsif active? && new_sold_units >= total_units && new_sold_units.positive?
      update!(status: :sold)
    end
  end

  # SF-B6 — a listing coming back from `sold` has to come back INTO the feed.
  #
  # Its 30-day clock kept running while it sat sold, so by the time it re-opens it
  # is usually already past `expires_at` — and reopening it without touching that
  # drops it straight into the seller's Expired tab (`expired_active` is `live` +
  # past expiry), where they have to go hunting for Renew to finish a fix they
  # just made. Refreshed ONLY when the expiry has actually passed: a listing with
  # three weeks left keeps them, and a listing that never had an expiry (nil
  # reads as "never expires" to `not_expired`) is not given one here.
  #
  # Inside `reconcile_sold_status!` and not in the SF-B6 callback so the SF-B4
  # correction path (undo a sale on a sold-out listing that has since expired)
  # gets the same treatment — it had the identical hole.
  def refreshed_expiry
    return {} unless expires_at.present? && expires_at.past?

    { expires_at: LISTING_LIFESPAN.from_now }
  end

  # SF-B6 — see the `after_update` registration above. Reads the CURRENT columns:
  # by the time an after_update callback runs, both are the values just saved.
  def reconcile_status_after_quantity_change
    reconcile_sold_status!(sold_units, quantity)
  end

  # SF-B6 — `quantity` may never fall below the units already sold.
  def quantity_covers_sold_units
    return if quantity.blank? || sold_units.blank?
    return if quantity >= sold_units
    # SF-B8 — an open hold can sit HIGHER than the units already sold, and when it
    # does `quantity_covers_held_units` is the rule that names the number; this one
    # steps aside so exactly one minimum is ever reported. A no-op for any listing
    # without a hold, which is almost all of them (held_units is then 0).
    return if hold_sets_quantity_floor?

    errors.add(
      :quantity,
      QUANTITY_BELOW_SOLD_UNITS,
      message: "cannot be less than the #{sold_units} #{'unit'.pluralize(sold_units)} already sold. " \
               "Set it to #{sold_units} or more, or undo a sale first."
    )
  end

  # SF-B8 — `quantity` may never fall below the units on hold for a buyer.
  #
  # Worded to read correctly through `errors.full_messages`, which prefixes the
  # attribute name: "Quantity cannot be less than the 10 units on hold for a
  # buyer. Release the hold first, or set it to 10 or more." Singularized at 1
  # like SF-B6's, though `quantity` is validated `greater_than: 0` so a one-unit
  # hold can never actually breach this floor.
  def quantity_covers_held_units
    return unless hold_sets_quantity_floor?

    held = held_units
    return if quantity >= held

    errors.add(
      :quantity,
      QUANTITY_BELOW_HELD_UNITS,
      message: "cannot be less than the #{held} #{'unit'.pluralize(held)} on hold for a buyer. " \
               "Release the hold first, or set it to #{held} or more."
    )
  end

  # SF-B8 — true when an open hold sets a STRICTLY higher floor under `quantity`
  # than the units already sold: the hold is then the number to report.
  #
  # Asked by BOTH quantity floors so they report exclusively. Without it a listing
  # that is below sold_units AND below held_units answers with two different
  # minimums ("set it to 8 or more" beside "set it to 10 or more"), and a seller
  # who obeys the smaller one is refused again — a contradictory pair rather than
  # an answer. Whichever floor is higher speaks; the other is silent; the number
  # the seller is given is always the number that actually works.
  #
  # Scoped to saves that actually CHANGE `quantity`, for two reasons:
  #
  #   * every other write on a listing (renew!, take_down!, a price edit, SF-B6's
  #     status reconcile) would otherwise pay for a `sale_transactions` lookup it
  #     has no use for. `held_units` reads `open_sale`, whose loaded-array guard
  #     only helps the eager-loaded feed — from a validation it is a real query.
  #   * a row already BELOW its hold must stay editable. Those rows exist: this
  #     bug has been accepting exactly that edit since SF-B2 shipped holds with a
  #     quantity. An unconditional rule would strand them — renew, unpublish and
  #     every unrelated edit refused, forever — which is the retroactive-validation
  #     trap SF-B7 was just written to soften, and the one
  #     `photo_required_to_publish` is scoped to the publish transition to avoid.
  #     Raising the quantity to the held count still fixes them, so does releasing
  #     the hold; nothing else is blocked in the meantime.
  def hold_sets_quantity_floor?
    return false if new_record? || quantity.blank?
    return false unless will_save_change_to_quantity?

    held_units > sold_units.to_i
  end

  # Rendered as an ordinary 422 with a field error, the same shape as any other
  # validation failure — the client already knows how to show it.
  def raise_capacity_error!(transaction, new_units, capacity)
    transaction.errors.add(
      :quantity,
      "must be between 1 and #{[ capacity, 1 ].max} for this listing's remaining stock (asked for #{new_units})"
    )
    raise ActiveRecord::RecordInvalid, transaction
  end

  # The one place a sold Transaction is created. `buyer_id` may be nil (SF-B3,
  # a sale with no counterparty account).
  def create_sold_sale!(buyer_id:, final_price:, units:)
    sale_transactions.create!(
      seller_id: user_id,
      buyer_id: buyer_id,
      final_price: final_price.presence || price,
      currency: currency,
      status: :sold,
      quantity: units,
      completed_at: Time.current
    )
  end

  # The newest SOLD row for this listing. Same loaded-vs-query guard as
  # #open_sale: filter the eager-loaded array in Ruby when there is one, so a
  # feed full of sold rows stays a constant number of queries.
  def latest_sold_sale
    if sale_transactions.loaded?
      sale_transactions.select(&:sold?).max_by(&:created_at)
    else
      sale_transactions.sold.order(created_at: :desc).first
    end
  end

  def record_price_history
    old_price, new_price = previous_changes[:price]
    return if old_price.nil? || new_price.nil?

    ListingPriceHistory.record_change!(
      listing:   self,
      old_price: old_price,
      new_price: new_price
    )
  end

  # True only while THIS save is taking an already-persisted draft to active.
  #
  # `persisted?` carries the weight: the status column defaults to 0, so a brand
  # new record reports `status_in_database == "draft"` even when it is being
  # created directly AS active (seeds, Administrate, factories) — without the
  # persisted check those creations would be treated as publishing and refused.
  # A reserved -> active reactivation is excluded too: there the previous status
  # is "reserved", not "draft".
  def publishing?
    persisted? && will_save_change_to_status? && active? && status_in_database == "draft"
  end

  def photo_required_to_publish
    return if images.attached?

    errors.add(:base, "Add at least one photo before publishing")
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
