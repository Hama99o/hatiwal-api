class SavedListing < ApplicationRecord
  belongs_to :user
  belongs_to :listing

  validates :listing_id, uniqueness: { scope: :user_id }

  before_create :snapshot_price_at_save

  scope :ordered, -> { order(created_at: :desc) }

  # True when the listing's current price is lower than the price it had
  # the moment the buyer saved it, and the listing is still live (a dropped
  # price on a SOLD or admin-removed listing is no longer an actionable
  # "come back and buy" signal).
  #
  # SF-B1 — `live?`, not `active?`: a price drop on a HELD listing is just as
  # real a signal to the buyer who saved it, and reserved listings are back in
  # the feed the price-drop badge decorates.
  def price_dropped?
    return false if listing.nil? || price_at_save.nil?

    listing.live? && listing.price < price_at_save
  end

  # Positive amount the price fell by, or nil when it did not drop.
  def price_drop_amount
    return nil unless price_dropped?

    price_at_save - listing.price
  end

  private

  def snapshot_price_at_save
    self.price_at_save ||= listing&.price
  end
end
