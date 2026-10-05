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
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  LOGO_MAX_SIZE = 5.megabytes

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
  enum :status, { active: 0, suspended: 1, pending: 2 }

  validates :name, presence: true, length: { in: NAME_LENGTH }
  validates :description, length: { maximum: DESCRIPTION_MAX }
  validates :address_line, presence: true, length: { maximum: ADDRESS_MAX }
  validates :phone, length: { maximum: PHONE_MAX }
  validates :latitude, :longitude, presence: true
  validates :logo, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: LOGO_MAX_SIZE }
  validates :cover, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: LOGO_MAX_SIZE }
  validate :location_in_service_area
  validate :hours_well_formed
  validate :one_shop_per_owner, on: :create

  before_validation :fill_province_from_point
  before_create :apply_approval_switch
  after_create :add_owner_as_member
  # The badge vouched for THIS name and address: changing either after
  # verification takes it off and puts the approved request back to `requested`
  # for an admin to re-check (docs/SHOPS.md, "Losing it").
  after_update :reopen_verification_after_change, if: -> { verified? && saved_change_to_identity? }

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

  # The one failure the shop form must name in the user's own words, as a
  # stable token for the 422 body (`code`); nil for anything else.
  def error_code
    base = errors.details[:base].map { |d| d[:error] }
    return :shop_limit_reached if base.include?(:one_shop_per_user)

    :outside_service_area if base.include?(:outside_service_area)
  end

  def verified? = verified_at.present?

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

  # Live product counts for many shops in ONE grouped query: { shop_id => n }.
  def self.live_listings_counts(shop_ids)
    Listing.live.not_expired.not_removed.where(shop_id: shop_ids).group(:shop_id).count
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
  def move_listings!(user, listing_ids, to_shop: true)
    scope = user.listings.where(id: listing_ids)
    scope = to_shop ? scope.where(shop_id: nil) : scope.where(shop_id: id)
    scope.update_all(shop_id: to_shop ? id : nil, updated_at: Time.current)
  end

  private

  def saved_change_to_identity?
    saved_change_to_name? || saved_change_to_address_line? || saved_change_to_latitude? || saved_change_to_longitude?
  end

  def reopen_verification_after_change
    approved = verification_requests.approved.order(decided_at: :desc).first
    update_columns(verified_at: nil, verified_by_id: nil, updated_at: Time.current)
    approved&.update!(status: :requested, decided_by: nil, decided_at: nil)
  end

  def location_in_service_area
    return if latitude.blank? || longitude.blank?

    errors.add(:base, :outside_service_area) unless ServiceArea.include?(latitude, longitude)
  end

  # { "sat" => [["08:00","18:00"]], "fri" => [] } — known days only, each a list
  # of [from, to] pairs in HH:MM with from < to. Empty or missing = not stated.
  def hours_well_formed
    return errors.add(:hours, :malformed) unless hours.is_a?(Hash)

    hours.each do |day, ranges|
      next errors.add(:hours, :malformed) unless DAYS.include?(day.to_s) && ranges.is_a?(Array)

      ranges.each do |range|
        ok = range.is_a?(Array) && range.size == 2 && range.all? { |t| t.is_a?(String) && TIME_FORMAT.match?(t) } && range[0] < range[1]
        errors.add(:hours, :malformed) unless ok
      end
    end
  end

  # Phase 1 rule: one shop per user (lifted in phase 2).
  def one_shop_per_owner
    errors.add(:base, :one_shop_per_user) if owner && Shop.exists?(owner_id: owner.id)
  end

  def fill_province_from_point
    return if province.present? || latitude.blank? || longitude.blank?

    self.province = ServiceArea.nearest_province(latitude, longitude)
  end

  def apply_approval_switch
    self.status = :pending if self.class.approval_required? && active?
  end

  def add_owner_as_member
    shop_members.create!(user: owner, role: :owner)
  end
end
