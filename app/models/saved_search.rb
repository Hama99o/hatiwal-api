class SavedSearch < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true
  # Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md): the listings announced.
  has_many :alert_hits, class_name: SavedSearchAlertHit.name, dependent: :delete_all

  validates :user_id, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :radius, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

  # Keep only the most recent N searches per user (the quick-filter history).
  MAX_PER_USER = 4
  # Saved-search alerts: at most this many FOLLOWED searches per user. They are
  # an explicit opt-in on top of the history above, and never pruned with it.
  MAX_ALERTS = 5

  # Attributes that define a "duplicate" filter combination.
  DEDUP_ATTRS = %i[location category_id price_min price_max latitude longitude radius query].freeze

  validates :query, length: { maximum: 100 }, allow_nil: true
  validate :alerts_within_limit, if: -> { alert? && (new_record? || will_save_change_to_alert?) }

  scope :recent, -> { order(created_at: :desc) }
  scope :alerted, -> { where(alert: true) }

  def self.for_user(user)
    where(user_id: user.id).recent
  end

  # Remove this user's other searches with the identical filter combination,
  # so re-applying the same filters just moves it to the top instead of piling
  # up duplicate chips.
  #
  # A followed sibling hands its alert over first: re-applying a followed search
  # from the chips must not silently unfollow it.
  def dedupe_siblings!
    siblings = user.saved_searches.where.not(id: id).where(DEDUP_ATTRS.index_with { |attr| self[attr] })
    followed = siblings.alerted.order(:last_alerted_at).last
    update_columns(alert: true, last_alerted_at: followed.last_alerted_at) if followed && !alert?
    siblings.destroy_all
  end

  # Trim the user's history down to the MAX_PER_USER most recent searches.
  # Followed searches (alert on) are not history: they are never trimmed.
  def self.prune_for(user, keep: MAX_PER_USER)
    history = user.saved_searches.where(alert: false)
    keep_ids = history.recent.limit(keep).pluck(:id)
    history.where.not(id: keep_ids).destroy_all
  end

  # Check if this is a location-based search
  def location_based?
    latitude.present? && longitude.present? && radius.present?
  end

  # Count browsable listings that match this saved search's stored filters and
  # were created after the user last viewed this chip (or after the search was
  # first saved when last_viewed_at is nil).
  #
  # Reuses the same Listing scopes used by the public Browse index so the
  # definition of "browsable" is never duplicated.
  #
  # The block-pair filter mirrors ListingPolicy::Scope#resolve so that a listing
  # from a seller the owner has blocked (or who blocked the owner) is never
  # counted — it would inflate the badge and then vanish when the filter is
  # actually applied through the policy-scoped browse index.
  def new_matches_count
    since = last_viewed_at || created_at
    matching_listings.where("listings.created_at > ?", since).count
  end

  # Saved-search alerts: does this listing match, exactly as Browse and the
  # chip badge would show it? Never the searcher's own listing.
  def matches?(listing)
    matching_listings.where.not(user_id: user_id).exists?(id: listing.id)
  end

  private

  # The browsable listings this search shows — THE one definition, shared by
  # the chip badge and the alerts.
  def matching_listings
    rel = Listing.browsable.excluding_blocked_pairs(user)
    rel = rel.by_category(category_id)  if category_id.present?
    rel = rel.price_at_least(price_min) if price_min.present?
    rel = rel.price_at_most(price_max)  if price_max.present?
    rel = rel.search(query)             if query.present?
    rel = rel.in_location(location)     if !location_based? && location.present?
    rel = rel.within_radius(latitude, longitude, radius) if location_based?
    rel
  end

  def alerts_within_limit
    followed = user.saved_searches.alerted.where.not(id: id).count
    errors.add(:alert, :alerts_limit, message: "You can follow at most #{MAX_ALERTS} searches.") if followed >= MAX_ALERTS
  end
end
