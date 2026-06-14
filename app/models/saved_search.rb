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
end
