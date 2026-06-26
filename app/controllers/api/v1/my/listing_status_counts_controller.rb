class Api::V1::My::ListingStatusCountsController < Api::V1::BaseController
  def show
    authorize Listing, :status_counts?

    base  = current_user.listings.not_removed
    # One grouped query for draft/active/reserved/sold raw counts.
    raw   = base.group(:status).count
    # One extra query for the "expired" virtual bucket (active past expiry).
    exp   = base.expired_active.count
    # The "active" tab only shows non-expired active listings.
    live  = (raw["active"] || 0) - exp

    render_ok({
      all:      base.count,
      draft:    raw["draft"]    || 0,
      active:   live,
      expired:  exp,
      reserved: raw["reserved"] || 0,
      sold:     raw["sold"]     || 0
    })
  end
end
