# SHOP-1 — a business identity on top of a normal account
# (hatiwal-mobile/docs/SHOPS.md). A shop belongs to its owner and only SELLS:
# buying is always personal. Listings posted while "selling as" the shop carry
# `listings.shop_id`.
class Shop < ApplicationRecord
  NAME_LENGTH = 2..50
  DESCRIPTION_MAX = 160
  ADDRESS_MAX = 160
  PHONE_MAX = 30
  DAYS = %w[sat sun mon tue wed thu fri].freeze
  # Date#wday (0 = Sunday) → our day keys.
  WDAY_KEYS = %w[sun mon tue wed thu fri sat].freeze
  # Shops keep local hours: Pakistan's provinces are on Asia/Karachi, the rest
  # (Afghanistan, and anything we cannot place) on Asia/Kabul.
  PAKISTAN_PROVINCES = [ "Punjab", "Sindh", "Khyber Pakhtunkhwa", "Balochistan", "Islamabad", "Gilgit-Baltistan", "Azad Kashmir" ].freeze
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  LOGO_MAX_SIZE = 5.megabytes
  # SHOP-2 — "the same shop can't be added twice" (one owner's own shops only):
  # the same normalized name this close, or the same address in the same city
  # (within ADDRESS_NEAR_KM when a city isn't stored).
  DUPLICATE_NAME_RADIUS_KM = 0.2
  ADDRESS_NEAR_KM = 5.0

  belongs_to :owner, class_name: User.name, inverse_of: :owned_shops
  belongs_to :category
  belongs_to :verified_by, class_name: AdminUser.name, optional: true

  has_many :shop_members, dependent: :destroy
  has_many :members, through: :shop_members, source: :user
  # A deleted shop's products go back to being the owner's personal listings
  # (the owner is moved to "Me" too — users.active_shop_id is nullified by FK).
  has_many :listings, dependent: :nullify

  # Verified shop (docs/SHOPS.md): applied for through VER-1's requests.
  has_many :verification_requests, as: :subject, dependent: :destroy, inverse_of: :subject

  has_one_attached :logo
  has_one_attached :cover

  # `pending` only exists while SHOP_APPROVAL_REQUIRED is on: the shop waits for
  # an admin before it appears. Off by default (owner, 2026-10-05).
  # `closed`: the owner closed it, or deleted their account (#close!). Kept,
  # soft, so its verification decisions and ID digest survive (owner, 2026-10-05:
  # a banned person must not verify again with the same ID).
  enum :status, { active: 0, suspended: 1, pending: 2, closed: 3 }

  validates :name, presence: true, length: { in: NAME_LENGTH }
  validates :description, length: { maximum: DESCRIPTION_MAX }
  validates :address_line, presence: true, length: { maximum: ADDRESS_MAX }
  validates :phone, length: { maximum: PHONE_MAX }
  validates :latitude, :longitude, presence: true
  validates :logo, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: LOGO_MAX_SIZE }
  validates :cover, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: LOGO_MAX_SIZE }
  validate :location_in_service_area
  validate :hours_well_formed
  validate :not_a_duplicate_of_own_shop

  before_validation :fill_province_from_point
  before_create :apply_approval_switch
  after_create :add_owner_as_member

  scope :visible, -> { active }
  scope :recent, -> { order(created_at: :desc) }

  # Whether new shops wait for an admin before they appear. A safety switch for
  # when fake shops become a problem; off unless the env says "true".
  def self.approval_required?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("SHOP_APPROVAL_REQUIRED", "false"))
  end

  # https://hatiwal.com/s/<id> when PUBLIC_SHARE_BASE_URL is set, like listings
  # (/l/) and users (/u/); nil otherwise (the app builds a deep link).
  def self.share_url_for(shop)
    base = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    return nil if base.blank?

    "#{base.chomp('/')}/s/#{shop.id}"
  end

  def member?(user)
    return false unless user

    shop_members.exists?(user_id: user.id)
  end

  # The failures the shop form must name in the user's own words, as a stable
  # token for the 422 body (`code`); nil for anything else.
  def error_code
    base = errors.details[:base].map { |d| d[:error] }
    return :shop_duplicate if base.include?(:duplicate_shop)

    :outside_service_area if base.include?(:outside_service_area)
  end

  # SHOP-2 — the owner's open shop this one would duplicate, or nil.
  attr_reader :duplicate_shop

  # Case, spaces, punctuation and zero-width marks ignored; Arabic and Persian
  # letter variants (ي/ی, ك/ک, ة/ه, أ/إ/آ → ا) and digits folded, so
  # "Safi  Store!" = "safi store" and "صافي" = "صافی".
  def self.normalize_for_duplicate(text)
    text.to_s.unicode_normalize(:nfkc)
        .tr("يىكةأإآ۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "یيکهااا01234567890123456789").tr("ي", "ی")
        .downcase.gsub(/[\p{P}\p{S}\p{Cf}\s]+/, "")
  end

  # Great-circle distance in km (the shop count per owner is tiny: done in Ruby).
  def self.distance_km(lat1, lng1, lat2, lng2)
    return Float::INFINITY if [ lat1, lng1, lat2, lng2 ].any?(&:nil?)

    rad = Math::PI / 180
    dlat = (lat2.to_f - lat1.to_f) * rad
    dlng = (lng2.to_f - lng1.to_f) * rad
    a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1.to_f * rad) * Math.cos(lat2.to_f * rad) * (Math.sin(dlng / 2)**2))
    6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  # Serializes one owner's shop writes, so two identical "Open my shop" taps
  # can't both pass the duplicate check. Call inside a transaction.
  def self.lock_owner!(owner_id)
    connection.execute(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?, ?)", 4_202, owner_id.to_i ]))
  end

  def verified? = verified_at.present?

  # ── Open now (server-side, in the shop's own time zone) ────────────────────
  def time_zone = PAKISTAN_PROVINCES.include?(province) ? "Asia/Karachi" : "Asia/Kabul"

  # true / false, or nil when the shop states no hours at all.
  def open_now(at: Time.current)
    return nil unless hours_stated?

    open_interval(at).present?
  end

  # The next open→closed or closed→open moment (in the shop's zone, ISO8601 by
  # the serializer); nil when there is none in the coming week or no hours.
  def next_change_at(at: Time.current)
    return nil unless hours_stated?

    now = at.in_time_zone(time_zone)
    current = open_interval(now)
    return current.last if current

    hour_intervals(now).map(&:first).select { |start| start > now }.min
  end

  def hours_stated? = hours.is_a?(Hash) && hours.any?

  # ── Losing the badge (docs/SHOPS.md, "Losing it") ──────────────────────────
  # The badge vouched for THIS name and address. After the owner changes either,
  # it comes off; the owner re-applies (the status card says "Your shop
  # name/address changed — verify again", VerificationStatus#name_changed?).
  # Decided requests are history and are never rewritten — the same rule as
  # User#drop_badge_after_name_change! (VER-1, 1988052). Called from the owner's
  # own edit (ShopsController#update), never as a callback. True when dropped.
  def drop_badge_after_identity_change!
    return false unless verified? && saved_change_to_identity?

    update_columns(verified_at: nil, verified_by_id: nil, updated_at: Time.current)
    true
  end

  # The open intervals around `now` as [start, end] times, merged so a range
  # that runs past midnight into the next day's first range reads as one.
  def hour_intervals(now)
    zone = ActiveSupport::TimeZone[time_zone]
    today = now.in_time_zone(time_zone).to_date
    raw = (-1..7).flat_map do |offset|
      date = today + offset
      Array(hours[WDAY_KEYS[date.wday]]).map do |from, to|
        start = zone.parse("#{date} #{from}")
        stop = zone.parse("#{to < from ? date + 1 : date} #{to}")
        [ start, stop ]
      end
    end
    raw.sort_by(&:first).each_with_object([]) do |(start, stop), merged|
      if merged.any? && start <= merged.last.last
        merged.last[1] = [ merged.last.last, stop ].max
      else
        merged << [ start, stop ]
      end
    end
  end

  def open_interval(at)
    now = at.in_time_zone(time_zone)
    hour_intervals(now).find { |start, stop| start <= now && now < stop }
  end

  def saved_change_to_identity?
    saved_change_to_name? || saved_change_to_address_line? || saved_change_to_latitude? || saved_change_to_longitude?
  end

  # ── Closing (the owner's "Close my shop", or their account deletion) ───────
  # Nothing of a closed shop stays public, but the row stays (status closed):
  #   - page 404, out of search / share link / Selling as / public counts
  #     (`visible` is active only);
  #   - logo, cover and verification photos purged; phone, address,
  #     description and the point blanked (the name stays for the admin);
  #   - every membership ends; anyone selling as it falls back to Me;
  #   - its products go back to the owner as personal listings (an account
  #     deletion has already taken them off with every other listing);
  #   - verification requests: files purged, document number + name blanked,
  #     open ones cancelled — the digest and the decisions are KEPT.
  def close!
    transaction do
      verification_requests.find_each do |request|
        request.purge_files!
        attrs = { document_number: nil, name_on_document: nil, updated_at: Time.current }
        attrs.merge!(status: VerificationRequest.statuses[:cancelled], decided_at: Time.current) if request.requested?
        request.update_columns(attrs)
      end
      logo.purge if logo.attached?
      cover.purge if cover.attached?
      listings.update_all(shop_id: nil, updated_at: Time.current)
      User.where(active_shop_id: id).update_all(active_shop_id: nil, updated_at: Time.current)
      shop_members.destroy_all # destroy, not delete: keeps the members' counters right
      update_columns(status: self.class.statuses[:closed], phone: nil, phone_public: false, address_line: nil,
                     description: nil, latitude: nil, longitude: nil, verified_at: nil, verified_by_id: nil,
                     updated_at: Time.current)
    end
  end

  # ── Admin moderation ───────────────────────────────────────────────────────
  # Suspended shops leave search (Listing.from_visible_shops); every member is
  # moved back to selling as themselves at once, not on their next request.
  def suspend!
    transaction do
      suspended!
      User.where(active_shop_id: id).update_all(active_shop_id: nil, updated_at: Time.current)
    end
  end

  def reactivate! = active!

  # The owner can never be removed (phase 3 will transfer ownership first).
  # Returns false for the owner row.
  def remove_member!(member)
    return false if member.owner?

    transaction do
      member.destroy!
      User.where(id: member.user_id, active_shop_id: id).update_all(active_shop_id: nil, updated_at: Time.current)
    end
    true
  end

  # ── Verification (VER-1's VerificationRequest, subject = this shop) ─────────
  def latest_verification_request
    verification_requests.where.not(status: :cancelled).order(created_at: :desc, id: :desc).first
  end

  # What stops this shop applying, as keys the clients translate. Empty = may apply.
  def verification_missing
    missing = []
    missing << "logo" unless logo.attached?
    missing << "location" if latitude.blank? || longitude.blank?
    missing << "live_product" if live_listings_count.zero?
    missing
  end

  def verification_granted!(admin) = update!(verified_at: Time.current, verified_by: admin)
  def verification_withdrawn! = update!(verified_at: nil, verified_by: nil)
  # The Support message goes to the owner, in the owner's language.
  def verification_notice_recipient = owner
  def verification_notice_key(decision) = { verified: :shop_verified, rejected: :shop_verification_rejected, revoked: :shop_badge_removed }.fetch(decision)
  def preferred_language = owner.preferred_language
  def full_name = name

  def logo_url = logo.attached? ? logo.url : nil

  def cover_url = cover.attached? ? cover.url : nil

  def live_listings_count = listings.live.not_expired.not_removed.count

  # The products `viewer` actually sees on this shop's page: the same rule as
  # GET /listings?shop_id= (a blocked pair's products and the viewer's own
  # "Not interested" hides drop out). A guest sees them all. The shop page's
  # "Products (n)" must never count what the list below it won't show (it gave
  # a block away to the blocked person).
  def listings_visible_to(viewer)
    self.class.visible_live_listings(viewer).where(shop_id: id)
  end

  # Live product counts for many shops in ONE grouped query: { shop_id => n },
  # as `viewer` sees them (nil = everyone's count).
  def self.live_listings_counts(shop_ids, viewer: nil)
    visible_live_listings(viewer).where(shop_id: shop_ids).group(:shop_id).count
  end

  def self.visible_live_listings(viewer)
    scope = Listing.live.not_expired.not_removed
    viewer ? scope.excluding_blocked_pairs(viewer).not_hidden_for(viewer) : scope
  end

  # Opening hours from the client: a Hash (JSON body) or a JSON string
  # (multipart form). Anything unparseable becomes a non-Hash, which the
  # `hours_well_formed` validation then rejects as a 422.
  def self.parse_hours(raw)
    raw = JSON.parse(raw) if raw.is_a?(String)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw
  rescue JSON::ParserError
    :unparseable
  end

  # Move the user's own listings into this shop (to_shop) or back to Me.
  # Returns how many moved. Someone else's listing is never touched.
  MOVE_LISTINGS_MAX = 200

  def move_listings!(user, listing_ids, to_shop: true)
    return 0 if to_shop && !active? # only an open shop takes products
    scope = user.listings.where(id: Array(listing_ids).first(MOVE_LISTINGS_MAX))
    scope = to_shop ? scope.where(shop_id: nil) : scope.where(shop_id: id)
    scope.update_all(shop_id: to_shop ? id : nil, updated_at: Time.current)
  end

  private


  def location_in_service_area
    return if latitude.blank? || longitude.blank?

    errors.add(:base, :outside_service_area) unless ServiceArea.include?(latitude, longitude)
  end

  # { "sat" => [["08:00","18:00"]], "fri" => [] } — known days only, each a list
  # of [from, to] pairs in HH:MM. to < from = closes after midnight
  # (["18:00", "02:00"] on fri = fri 18:00 → sat 02:00); from == to is refused.
  # [] = closed that day; a missing day = not stated.
  def hours_well_formed
    return errors.add(:hours, :malformed) unless hours.is_a?(Hash)

    hours.each do |day, ranges|
      next errors.add(:hours, :malformed) unless DAYS.include?(day.to_s) && ranges.is_a?(Array)

      ranges.each do |range|
        ok = range.is_a?(Array) && range.size == 2 && range.all? { |t| t.is_a?(String) && TIME_FORMAT.match?(t) } && range[0] != range[1]
        errors.add(:hours, :malformed) unless ok
      end
    end
  end

  # SHOP-2: several shops per owner, but never the same one twice.
  def not_a_duplicate_of_own_shop
    @duplicate_shop = nil
    return if owner_id.nil? || closed?
    return unless new_record? || will_save_change_to_name? || will_save_change_to_address_line? ||
                  will_save_change_to_latitude? || will_save_change_to_longitude? || will_save_change_to_city?

    @duplicate_shop = Shop.where(owner_id: owner_id).where.not(status: :closed).where.not(id: id).find { |other| duplicate_of?(other) }
    errors.add(:base, :duplicate_shop) if @duplicate_shop
  end

  def duplicate_of?(other)
    km = self.class.distance_km(latitude, longitude, other.latitude, other.longitude)
    same_name = (n = self.class.normalize_for_duplicate(name)).present? && n == self.class.normalize_for_duplicate(other.name)
    return true if same_name && km <= DUPLICATE_NAME_RADIUS_KM

    same_address = (a = self.class.normalize_for_duplicate(address_line)).present? && a == self.class.normalize_for_duplicate(other.address_line)
    return false unless same_address

    city.present? && other.city.present? ? self.class.normalize_for_duplicate(city) == self.class.normalize_for_duplicate(other.city) : km <= ADDRESS_NEAR_KM
  end

  # The province always follows the pin (the pin is the truth; a typed
  # province could disagree with it). Kept as given when no capital is near.
  def fill_province_from_point
    return if latitude.blank? || longitude.blank?
    return unless new_record? || will_save_change_to_latitude? || will_save_change_to_longitude?

    self.province = ServiceArea.nearest_province(latitude, longitude) || province
  end

  def apply_approval_switch
    self.status = :pending if self.class.approval_required? && active?
  end

  def add_owner_as_member
    shop_members.create!(user: owner, role: :owner)
  end
end
