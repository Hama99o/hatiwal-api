namespace :listings do
  desc "Re-date every listing's hold from the hold itself (SF-B10 backfill) — " \
       "sets listings.reserved_at to the open Transaction's created_at, or NULL " \
       "when no hold is in place. Needed once because a multi-unit batch keeps " \
       "status `active` while it holds units (SF-B2), so the old status-driven " \
       "callback never dated a batch's hold and those rows still read NULL. " \
       "Safe to run any time — fully idempotent, and skips rows already correct."
  task reconcile_hold_stamps: :environment do
    # Only rows that could possibly be wrong: something is holding units, or a
    # stamp exists that may no longer have a hold behind it. A draft/active
    # listing with no ledger row and no stamp is already correct and is skipped
    # entirely rather than loaded.
    scope = Listing.where(id: Transaction.select(:listing_id))
                   .or(Listing.where.not(reserved_at: nil))

    changed = 0
    scope.find_each do |listing|
      before = listing.reserved_at
      listing.reconcile_hold_stamp!
      changed += 1 if listing.reserved_at != before
    end

    puts "Reconciled reserved_at on #{changed} listing(s)."
  end
end
