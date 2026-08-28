require "rails_helper"

# SF-B10 — the backfill lever for `listings.reserved_at`.
#
# The fix itself only re-dates a listing the next time something touches its
# hold, and the rows that were WRONG are precisely the ones nobody is touching:
# a multi-unit batch quietly holding units, whose `status` stayed `active` so the
# old callback never dated the hold at all. This task re-derives the column for
# the whole table from the ledger, so existing data is not left waiting for a
# seller to release and re-place a hold they are happy with.
RSpec.describe "listings:reconcile_hold_stamps", type: :task do
  before { Rake::Task["listings:reconcile_hold_stamps"].reenable }

  def invoke!
    Rake::Task["listings:reconcile_hold_stamps"].invoke
  end

  it "dates a batch whose hold predates the fix (status active, reserved_at NULL)" do
    seller  = create(:user)
    buyer   = create(:user)
    listing = create(:listing, :active, user: seller, quantity: 15)
    hold    = create(:transaction, listing: listing, seller: seller, buyer: buyer, quantity: 10)
    # The exact pre-fix state: a hold in place, no date, and the status is no
    # evidence either way.
    listing.update_columns(reserved_at: nil)

    expect { invoke! }.to output(/Reconciled reserved_at on 1 listing\(s\)\./).to_stdout

    listing.reload
    expect(listing).to be_active
    expect(listing.held_units).to eq(10)
    expect(listing.reserved_at.to_i).to eq(hold.created_at.to_i)
  end

  it "clears a stamp left behind on a listing with no hold" do
    listing = create(:listing, :active, user: create(:user))
    listing.update_columns(reserved_at: 3.days.ago)

    expect { invoke! }.to output(/Reconciled reserved_at on 1 listing\(s\)\./).to_stdout

    expect(listing.reload.reserved_at).to be_nil
  end

  it "does not re-date a sold listing's completed sale as a hold" do
    seller  = create(:user)
    buyer   = create(:user)
    listing = create(:listing, :sold, user: seller)
    create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)
    listing.update_columns(reserved_at: nil)

    invoke!

    expect(listing.reload.reserved_at).to be_nil
  end

  it "is idempotent — a second run changes nothing" do
    seller  = create(:user)
    buyer   = create(:user)
    listing = create(:listing, :active, user: seller, quantity: 15)
    create(:transaction, listing: listing, seller: seller, buyer: buyer, quantity: 4)
    invoke!
    stamp = listing.reload.reserved_at
    expect(stamp).to be_present

    Rake::Task["listings:reconcile_hold_stamps"].reenable
    expect { invoke! }.to output(/Reconciled reserved_at on 0 listing\(s\)\./).to_stdout
    expect(listing.reload.reserved_at.to_i).to eq(stamp.to_i)
  end

  it "leaves alone (and never loads) a listing that has neither a ledger row nor a stamp" do
    listing = create(:listing, :active, user: create(:user))

    expect { invoke! }.to output(/Reconciled reserved_at on 0 listing\(s\)\./).to_stdout
    expect(listing.reload.reserved_at).to be_nil
  end
end
