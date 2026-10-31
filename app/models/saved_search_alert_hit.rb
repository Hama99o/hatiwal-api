# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §1.2): one listing matched
# one followed search, once. `alerted_at` is set when a push announced it (or
# when it went stale before one could).
class SavedSearchAlertHit < ApplicationRecord
  belongs_to :saved_search, class_name: SavedSearch.name
  belongs_to :listing, class_name: Listing.name

  scope :unannounced, -> { where(alerted_at: nil) }
end
