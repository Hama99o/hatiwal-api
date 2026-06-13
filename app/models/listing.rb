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

  scope :active,      -> { where(status: :active) }
  scope :ordered,     -> { order(created_at: :desc) }
  scope :by_category, ->(id) { where(category_id: id) }
  scope :by_seller,   ->(id) { where(user_id: id) }
  scope :browsable,   -> { active.ordered }

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
