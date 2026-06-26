class SavedSearch < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true

  validates :user_id, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :radius, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

  # Keep only the most recent N searches per user (the quick-filter history).
  MAX_PER_USER = 4

  # Attributes that define a "duplicate" filter combination.
  DEDUP_ATTRS = %i[location category_id price_min price_max latitude longitude radius].freeze

  scope :recent, -> { order(created_at: :desc) }

  def self.for_user(user)
    where(user_id: user.id).recent
  end

  # Remove this user's other searches with the identical filter combination,
  # so re-applying the same filters just moves it to the top instead of piling
  # up duplicate chips.
  def dedupe_siblings!
    user.saved_searches
        .where.not(id: id)
        .where(DEDUP_ATTRS.index_with { |attr| self[attr] })
        .destroy_all
  end

  # Trim the user's history down to the MAX_PER_USER most recent searches.
  def self.prune_for(user, keep: MAX_PER_USER)
    keep_ids = user.saved_searches.recent.limit(keep).pluck(:id)
    user.saved_searches.where.not(id: keep_ids).destroy_all
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

    rel = Listing.browsable.excluding_blocked_pairs(user)
    rel = rel.by_category(category_id)  if category_id.present?
    rel = rel.price_at_least(price_min) if price_min.present?
    rel = rel.price_at_most(price_max)  if price_max.present?
    rel = rel.in_location(location)     if !location_based? && location.present?
    rel = rel.within_radius(latitude, longitude, radius) if location_based?

    rel.where("listings.created_at > ?", since).count
  end
end
