class ListingPriceHistory < ApplicationRecord
  belongs_to :listing

  validates :old_price, presence: true, numericality: { greater_than: 0 }
  validates :new_price, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true, inclusion: { in: %w[AFN USD EUR] }
  validates :changed_at, presence: true

  # A price reduction — old > new.
  scope :reductions, -> { where("new_price < old_price") }

  # Records within the last N days.
  scope :recent, ->(days = 14) { where("changed_at >= ?", days.days.ago) }

  # Ordered newest first.
  scope :newest_first, -> { order(changed_at: :desc) }

  # Create a history entry unconditionally. The caller (Listing model) is
  # responsible for checking whether the price actually changed.
  def self.record_change!(listing:, old_price:, new_price:)
    create!(
      listing:    listing,
      old_price:  old_price,
      new_price:  new_price,
      currency:   listing.currency,
      changed_at: Time.current
    )
  end

  # Percent reduction rounded to the nearest integer (positive value).
  # Returns 0 if not actually a reduction.
  def drop_percent
    return 0 if old_price <= 0 || new_price >= old_price

    ((old_price - new_price) / old_price * 100).round
  end
end
