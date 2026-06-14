class ListingView < ApplicationRecord
  belongs_to :user
  belongs_to :listing

  validates :listing_id, uniqueness: { scope: :user_id }

  # Record (or refresh) that a user has opened a listing. Safe under concurrent
  # opens: if another request wins the insert race (unique index), we just
  # refresh the existing row instead of raising RecordNotUnique.
  def self.record!(user, listing)
    view = find_or_initialize_by(user_id: user.id, listing_id: listing.id)
    view.last_viewed_at = Time.current
    view.save!
    view
  rescue ActiveRecord::RecordNotUnique
    existing = find_by(user_id: user.id, listing_id: listing.id)
    existing&.update(last_viewed_at: Time.current)
    existing
  end
end
