class ListingView < ApplicationRecord
  belongs_to :user
  belongs_to :listing

  validates :listing_id, uniqueness: { scope: :user_id }

  # Record that a user has opened a listing. Returns a two-element array:
  #   [view_record, newly_created?]
  #
  # Newly created means this is the user's first-ever view of the listing —
  # the caller uses this to decide whether to increment views_count.
  # Safe under concurrent opens: a duplicate-key race is rescued and treated
  # as an existing (not new) view.
  def self.record!(user, listing)
    view = find_or_initialize_by(user_id: user.id, listing_id: listing.id)
    newly_created = view.new_record?
    view.last_viewed_at = Time.current
    view.save!
    [ view, newly_created ]
  rescue ActiveRecord::RecordNotUnique
    existing = find_by(user_id: user.id, listing_id: listing.id)
    existing&.update(last_viewed_at: Time.current)
    [ existing, false ]
  end

  # Returns an array of {date:, count:} hashes for the last +days+ days,
  # always filling in 0 for days with no views. Each day counts distinct
  # viewer_id values whose last_viewed_at falls on that calendar date.
  #
  # Example result (7 entries, oldest → newest):
  #   [
  #     { date: "2026-06-11", count: 0 },
  #     { date: "2026-06-12", count: 3 },
  #     ...
  #     { date: "2026-06-17", count: 1 }
  #   ]
  def self.daily_counts_for_listing(listing_id, days: 7)
    today      = Date.current
    # start_date is (days-1) days ago so the range [start_date .. today]
    # spans exactly `days` calendar entries (inclusive of today).
    start_date = (days - 1).days.ago.to_date

    # Distinct viewer count per calendar day (using app timezone via AT TIME ZONE).
    # We cast last_viewed_at to the database session timezone (UTC = app default)
    # so DATE() grouping matches Ruby's Date.current.
    rows = where(listing_id: listing_id)
             .where(last_viewed_at: start_date.beginning_of_day..today.end_of_day)
             .group("DATE(last_viewed_at AT TIME ZONE 'UTC')")
             .count("DISTINCT user_id")
    # rows is a Hash: { Date => Integer }

    (0...days).map do |offset|
      date = start_date + offset
      { date: date.to_s, count: rows[date] || 0 }
    end
  end
end
