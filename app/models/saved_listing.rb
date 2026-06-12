class SavedListing < ApplicationRecord
  belongs_to :user
  belongs_to :listing

  validates :listing_id, uniqueness: { scope: :user_id }

  scope :ordered, -> { order(created_at: :desc) }
end
