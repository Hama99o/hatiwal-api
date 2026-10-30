# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §1.2): a listing just went
# live; which FOLLOWED searches does it match?
#
# A cheap SQL pass picks the candidates on the indexed columns (alert on, the
# account switch on, not the seller, the listing's category or its parent or
# no category, the price inside the range). Then each candidate is checked with
# SavedSearch#matches? — the same scopes Browse and the chip badge use, keyword
# and location included. A match is counted once per (search, listing) and its
# push is left to SavedSearchAlertJob (batching, caps, quiet hours).
class SavedSearchMatchJob < ApplicationJob
  queue_as :default

  def perform(listing_id)
    listing = Listing.find_by(id: listing_id)
    return unless listing

    candidates(listing).find_each do |search|
      next unless search.matches?(listing)
      next unless first_hit?(search, listing)

      SavedSearch.update_counters(search.id, pending_alert_count: 1)
      SavedSearchAlerts.schedule(search.reload)
    end
  end

  private

  def candidates(listing)
    category_ids = [ listing.category_id, listing.category&.parent_id ].compact
    SavedSearch.alerted
               .joins(:user).where(users: { saved_search_alerts: true })
               .where.not(user_id: listing.user_id)
               .where("saved_searches.category_id IS NULL OR saved_searches.category_id IN (?)", category_ids)
               # price is a decimal, the bounds integers: compare as numeric.
               .where("saved_searches.price_min IS NULL OR saved_searches.price_min <= CAST(? AS numeric)", listing.price.to_s)
               .where("saved_searches.price_max IS NULL OR saved_searches.price_max >= CAST(? AS numeric)", listing.price.to_s)
               .includes(:user)
  end

  # true the first time this listing matches this search (a listing that goes
  # live twice — relaunched, reactivated — is announced once).
  def first_hit?(search, listing)
    SavedSearchAlertHit.insert_all(
      [ { saved_search_id: search.id, listing_id: listing.id, created_at: Time.current, updated_at: Time.current } ],
      unique_by: %i[saved_search_id listing_id]
    ).rows.any?
  end
end
