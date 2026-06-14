class Listing < ApplicationRecord
  belongs_to :user
  belongs_to :category
  has_many_attached :images
  has_many :saved_listings, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :reports, as: :reportable, dependent: :destroy

  enum :status, { draft: 0, active: 1, reserved: 2, sold: 3 }

  validates :title, presence: true, length: { maximum: 150 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  CURRENCIES = %w[AFN USD EUR].freeze
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :category, presence: true

  EARTH_RADIUS_KM = 6371

  scope :active,      -> { where(status: :active) }
  scope :ordered,     -> { order(created_at: :desc) }
  scope :by_category, ->(id) { where(category_id: id) }
  scope :by_seller,   ->(id) { where(user_id: id) }
  scope :browsable,   -> { active.ordered }
  scope :price_at_least, ->(min) { where("price >= ?", min) }
  scope :price_at_most,  ->(max) { where("price <= ?", max) }
  scope :in_location,    ->(text) { where("LOWER(location) LIKE ?", "%#{text.to_s.downcase.strip}%") }

  # Listings whose coordinates fall within `km` kilometers of (lat, lng),
  # using the Haversine formula. LEAST/GREATEST clamp the acos argument to
  # [-1, 1] so floating-point drift can't raise a domain error.
  def self.within_radius(lat, lng, km)
    return all if lat.blank? || lng.blank? || km.blank?

    where.not(latitude: nil, longitude: nil).where(
      "#{EARTH_RADIUS_KM} * acos(LEAST(1, GREATEST(-1, " \
      "cos(radians(?)) * cos(radians(latitude)) * cos(radians(longitude) - radians(?)) + " \
      "sin(radians(?)) * sin(radians(latitude))))) <= ?",
      lat.to_f, lng.to_f, lat.to_f, km.to_f
    )
  end

  before_save :set_published_at, if: -> { active? && published_at.nil? }
  before_save :set_reserved_at,  if: -> { reserved? && reserved_at.nil? }
  before_save :set_sold_at,      if: -> { sold? && sold_at.nil? }

  def self.search(query)
    return all if query.blank?

    words = query.to_s.strip.split(/\s+/)
    result = all

    words.each do |word|
      term = "%#{word.downcase}%"
      result = result.where(
        "LOWER(title) LIKE ? OR LOWER(description) LIKE ?",
        term, term
      )
    end

    result
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

  private

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
