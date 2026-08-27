class Api::V1::My::ListingStatusCountsController < Api::V1::BaseController
  def show
    authorize Listing, :status_counts?

    base  = current_user.listings.not_removed
    # One grouped query for draft/active/reserved/sold raw counts.
    raw   = base.group(:status).count
    # One extra query for the "expired" virtual bucket (active past expiry).
    exp   = base.expired_active.count
    # The "active" tab shows non-expired LIVE listings — active plus reserved
    # (SF-B1, `Listing.for_status_filter("active")` => `live.not_expired`). The
    # badge has to count what the tab actually returns, or a seller sees "3" over
    # a list of 4. `exp` (the expired bucket) is likewise `live`-based, so the
    # two buckets still partition cleanly.
    live  = (raw["active"] || 0) + (raw["reserved"] || 0) - exp

    render_ok({
      all:      base.count,
      draft:    raw["draft"]    || 0,
      active:   live,
      expired:  exp,
      # Raw enum split, kept as-is: no client renders a "Reserved" tab any more
      # (those rows are inside `active` now), but the honest per-status number
      # costs nothing and removing a key from a live payload breaks clients.
      reserved: raw["reserved"] || 0,
      sold:     raw["sold"]     || 0
    })
  end
end
