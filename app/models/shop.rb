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
  # SHOP-3: the owner plus at most 19 staff.
  TEAM_LIMIT = 20
  # SHOP-2 — "the same shop can't be added twice" (one owner's own shops only):
  # the same normalized name this close, or the same address in the same city
  # (within ADDRESS_NEAR_KM when a city isn't stored).
  DUPLICATE_NAME_RADIUS_KM = 0.2
  ADDRESS_NEAR_KM = 5.0

  belongs_to :owner, class_name: User.name, inverse_of: :owned_shops
  belongs_to :category
  belongs_to :verified_by, class_name: AdminUser.name, optional: true

  has_many :shop_members, dependent: :destroy
  # SHOP-3 — the team: invitations and who changed what.
  has_many :invites, class_name: ShopInvite.name, dependent: :destroy
  has_many :audit_events, class_name: ShopAuditEvent.name, dependent: :destroy
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

  # ── SHOP-3: the team (docs/SHOPS.md, "Phase 3 — the team") ─────────────────
  def owner?(user) = user.present? && owner_id == user.id
  def team_full? = shop_members.count >= TEAM_LIMIT

  # The owner invites someone as Staff: a plain link (email nil) or a
  # confirmed-email invite. Raises ShopInvite::Refused with the code to show.
  def invite!(by:, email: nil)
    email = email.to_s.strip.downcase.presence
    raise ShopInvite::Refused.new(:shop_unavailable) unless active?
    raise ShopInvite::Refused.new(:cannot_invite_self) if email && by.email.to_s.casecmp?(email)
    raise ShopInvite::Refused.new(:already_member) if email && members.where("LOWER(users.email) = ?", email).exists?
    raise ShopInvite::Refused.new(:team_full) if team_full?

    invite = self.class.transaction do
      team_actor!(by, :owner, :manager)
      self.class.lock_owner!(owner_id) # one owner's invites are counted one at a time
      if invites.where("shop_invites.created_at > ?", 1.day.ago).count >= ShopInvite::DAILY_LIMIT
        raise ShopInvite::Refused.new(:too_many_invites, status: :too_many_requests)
      end

      created = invites.create!(invited_by: by, email: email, role: :staff)
      ShopAuditEvent.record!(self, :invited, actor: by, invite_id: created.id, by_email: email.present?)
      created
    end
    if email && (invitee = User.find_by("LOWER(email) = ?", email)) && invitee.confirmed_at.present?
      ShopTeamPushJob.perform_later("shop_invite", invitee.id, id, by.id, nil, invite.id)
      SupportNoticeJob.enqueue(invitee, :shop_invite_received, shop: self, invite: invite)
    end
    invite
  end

  # The owner removes anyone but themselves; a manager removes STAFF only.
  def remove_team_member!(user, by:)
    transaction do
      actor = team_actor!(by, :owner, :manager)
      member = shop_members.find_by(user_id: user.id)
      raise ShopInvite::Refused.new(:not_a_member, status: :not_found) unless member
      raise ShopInvite::Refused.new(:owner_cannot_leave) if member.owner?
      raise ShopInvite::Refused.new(:forbidden, status: :forbidden) if !actor.owner? && !member.staff?

      drop_member!(member, :removed, actor: by)
    end
  end

  # The owner changes a member's role (manager ⇄ staff). The owner's own role
  # only changes by a transfer.
  def change_role!(user, role:, by:)
    member = shop_members.find_by(user_id: user.id)
    raise ShopInvite::Refused.new(:not_a_member, status: :not_found) unless member
    raise ShopInvite::Refused.new(:cannot_change_owner) if member.owner?
    raise ShopInvite::Refused.new(:invalid_role) unless %w[manager staff].include?(role.to_s)
    return member if member.role == role.to_s

    from = member.role
    transaction do
      team_actor!(by, :owner)
      member.update!(role: role.to_s)
      ShopAuditEvent.record!(self, :role_changed, actor: by, target_user: user, from: from, to: role.to_s)
    end
    ShopTeamPushJob.perform_later("shop_membership_changed", user.id, id, by.id, "role_changed")
    SupportNoticeJob.enqueue(user, :shop_role_changed, shop: self)
    cancel_request_if_applicant_gone!(user)
    drop_badge_if_applicant_gone!(user)
    member
  end

  # The owner hands the shop to an existing member, who becomes the owner; the
  # old owner stays as a MANAGER. Shop chats follow (their seller is the owner).
  # A Verified badge is dropped: it vouched for the old owner's e-Tazkira.
  def transfer_ownership!(new_owner, by:)
    raise ShopInvite::Refused.new(:cannot_transfer_to_self) if new_owner.id == owner_id
    raise ShopInvite::Refused.new(:shop_unavailable) unless active?

    target = shop_members.find_by(user_id: new_owner.id)
    raise ShopInvite::Refused.new(:not_a_member) unless target
    raise ShopInvite::Refused.new(:verification_pending) if verification_requests.requested.exists?

    old_owner_id = owner_id
    was_verified = verified?
    transaction do
      lock!
      team_actor!(by, :owner)
      shop_members.find_by!(user_id: old_owner_id).update!(role: :manager)
      target.update!(role: :owner)
      chats = Conversation.where(shop_id: id)
      chats.where(seller_id: old_owner_id).where.not(buyer_id: new_owner.id)
           .update_all(seller_id: new_owner.id, updated_at: Time.current)
      update_columns(owner_id: new_owner.id, verified_at: nil, verified_by_id: nil, updated_at: Time.current)
      ShopAuditEvent.record!(self, :transferred, actor: by, target_user: new_owner, from: old_owner_id, to: new_owner.id,
                                                 badge_dropped: was_verified)
    end
    ShopTeamPushJob.perform_later("shop_owner_changed", new_owner.id, id, by.id)
    old_owner = User.find_by(id: old_owner_id)
    SupportNoticeJob.enqueue(new_owner, :shop_ownership_received, shop: self, actor: old_owner)
    SupportNoticeJob.enqueue(old_owner, :shop_ownership_handed_over, shop: self, actor: new_owner)
    reload
  end

  # A Staff member or a manager leaves; the owner can't (transfer first).
  def leave!(user)
    member = shop_members.find_by(user_id: user.id)
    raise ShopInvite::Refused.new(:not_a_member, status: :forbidden) unless member
    raise ShopInvite::Refused.new(:owner_cannot_leave) if member.owner?

    drop_member!(member, :left, actor: user)
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

  # ── The badge vouches for its APPLICANT (owner decision, 2026-10-08) ───────
  # The owner or a manager applies with their own e-Tazkira. If that person
  # later stops being the owner or a manager here (leaves, is removed, is made
  # Staff), the badge comes off — the same as an ownership transfer — and the
  # shop's Support thread says so; the owner or a manager re-applies.
  def badge_applicant
    return nil unless verified?

    verification_requests.approved.order(decided_at: :desc).first&.requested_by
  end

  def drop_badge_if_applicant_gone!(user)
    applicant = badge_applicant
    return false unless applicant && applicant.id == user.id
    return false if ShopPolicy.new(user, self).apply_verification?

    update_columns(verified_at: nil, verified_by_id: nil, updated_at: Time.current)
    ShopAuditEvent.record!(self, :badge_dropped, actor: nil, target_user: user, reason: "applicant_left")
    SupportNoticeJob.enqueue(owner, :shop_badge_applicant_left, shop: self, actor: user)
    true
  end

  # The same for a request still under review (edge-case pass 2026-10-08): an
  # admin must never approve a badge for someone who can no longer apply. It is
  # cancelled and its ID photos deleted at once, as if they had cancelled it.
  def cancel_request_if_applicant_gone!(user)
    return false if ShopPolicy.new(user, self).apply_verification?

    request = verification_requests.requested.find_by(requested_by_id: user.id)
    return false unless request

    request.cancel!
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
      # SHOP-3 (owner default, 2026-10-06): the shop's goods belong to the shop,
      # so a product a STAFF member posted goes to the OWNER, never to the staff
      # member's personal listings. Then every product leaves the closed shop.
      listings.where.not(user_id: owner_id).update_all(user_id: owner_id, updated_at: Time.current)
      listings.update_all(shop_id: nil, updated_at: Time.current)
      User.where(active_shop_id: id).update_all(active_shop_id: nil, updated_at: Time.current)
      # SHOP-3: pending invites die with the shop; each Staff member is told.
      invites.pending.update_all(status: ShopInvite.statuses[:cancelled], decided_at: Time.current, updated_at: Time.current)
      shop_members.staff.pluck(:user_id).each do |user_id|
        ShopTeamPushJob.perform_later("shop_membership_changed", user_id, id, nil, "closed")
      end
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
  # The admin removes a member (moderation). Same effect as the owner's
  # remove_team_member!, audited (SHOP-3) with no app actor.
  def remove_member!(member)
    return false if member.owner?

    drop_member!(member, :removed, actor: nil, by_admin: true)
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

  # A shop's reviews (owner, 2026-10-06): what BUYERS wrote about sales of THIS
  # shop's products (sale pinned to the shop when it was recorded). Never a
  # review of the owner as a buyer, never the owner's personal sales.
  def reviews
    Review.visible.of_seller.joins(:sale).where(transactions: { shop_id: id })
  end

  # [average rating (Float or nil), count] in one query.
  def review_stats
    @review_stats ||= begin
      avg, count = reviews.pick(Arel.sql("AVG(reviews.rating)"), Arel.sql("COUNT(reviews.id)"))
      [ avg&.to_f&.round(1), count.to_i ]
    end
  end

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

  # Edge-case pass 2026-10-08: the controller authorizes, then calls the model;
  # a role change landing in between must not let the OLD role act (a manager
  # just made Staff removing someone, an old owner changing roles). Re-checked
  # here on the actor's membership row, locked until the action commits, so a
  # concurrent change_role!/transfer (which writes that row) waits or is seen.
  def team_actor!(by, *roles)
    actor = by && shop_members.lock.find_by(user_id: by.id)
    raise ShopInvite::Refused.new(:forbidden, status: :forbidden) unless actor && roles.map(&:to_s).include?(actor.role)

    actor
  end

  def add_owner_as_member
    shop_members.create!(user: owner, role: :owner)
  end

  # Removed or left: the person drops back to Me at once, keeps their personal
  # account, and (removed) is told.
  def drop_member!(member, action, actor:, **data)
    transaction do
      # The shop keeps what was posted for it: the leaving member's products
      # become the owner's, the same hand-over close! does (review 2026-10-08).
      listings.where(user_id: member.user_id).where.not(user_id: owner_id)
              .update_all(user_id: owner_id, updated_at: Time.current)
      member.destroy!
      User.where(id: member.user_id, active_shop_id: id).update_all(active_shop_id: nil, updated_at: Time.current)
      ShopAuditEvent.record!(self, action, actor: actor, target_user: member.user, **data)
    end
    cancel_request_if_applicant_gone!(member.user)
    drop_badge_if_applicant_gone!(member.user)
    if action == :removed
      ShopTeamPushJob.perform_later("shop_membership_changed", member.user_id, id, actor&.id, "removed")
      SupportNoticeJob.enqueue(member.user, :shop_member_removed, shop: self)
    end
    member
  end
end
