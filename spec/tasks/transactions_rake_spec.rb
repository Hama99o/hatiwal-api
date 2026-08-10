require "rails_helper"

# TASK-TX02 (review fix, LOW — "the recovery lever has no spec, so no
# operator knows it exists or that it works"): covers
# `bin/rails transactions:recompute_counters` (lib/tasks/transactions.rake),
# the documented repair path for the admin-dashboard bypass described on
# Transaction#bump_trust_counters! (ListingDashboard::FORM_ATTRIBUTES permits
# `:status` directly, letting an admin re-open a sold Listing and the seller
# complete the sale a second time — over-counting the live incremental bump
# with no live decrement path).
#
# Reuses the exact reproduction from User#recompute_transaction_counters!'s
# own spec (spec/models/user_spec.rb) so the task-level test proves the SAME
# guarantee end-to-end, not just that the method it delegates to works.
RSpec.describe "transactions:recompute_counters", type: :task do
  before do
    Rake::Task["transactions:recompute_counters"].reenable
  end

  it "recomputes every drifted user's sold_count/bought_count from the transactions table" do
    seller = create(:user)
    buyer  = create(:user)
    listing = create(:listing, :active, user: seller)
    create(:conversation, listing: listing, seller: seller, buyer: buyer)
    create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)

    # Simulate drift exactly like the model-level spec does — a manual DB fix
    # or the admin-dashboard bypass corrupting the denormalized counters.
    seller.update_columns(sold_count: 99)
    buyer.update_columns(bought_count: 99)

    expect { Rake::Task["transactions:recompute_counters"].invoke }
      .to output(/Recomputed sold_count\/bought_count for \d+ users\./).to_stdout

    expect(seller.reload.sold_count).to eq(1)
    expect(buyer.reload.bought_count).to eq(1)
  end

  it "repairs the admin-dashboard double-count bypass (two sold Transaction rows on one listing)" do
    seller  = create(:user)
    buyer   = create(:user)
    listing = create(:listing, :sold, user: seller)
    create(:conversation, listing: listing, seller: seller, buyer: buyer)
    # Two sold Transaction rows on the SAME listing — the bypass this task
    # exists to repair (see Transaction#bump_trust_counters!'s comment).
    create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)
    create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)
    # The live incremental bump already over-counted by +1 per extra sold
    # Transaction — reproduce that drifted starting state directly.
    seller.update_columns(sold_count: 2)
    buyer.update_columns(bought_count: 2)

    Rake::Task["transactions:recompute_counters"].invoke

    expect(seller.reload.sold_count).to eq(1)
    expect(buyer.reload.bought_count).to eq(1)
  end

  it "is a no-op for a user with no sales at all (resets counters to 0)" do
    seller = create(:user)
    seller.update_columns(sold_count: 5, bought_count: 5)

    Rake::Task["transactions:recompute_counters"].invoke

    expect(seller.reload.sold_count).to eq(0)
    expect(seller.reload.bought_count).to eq(0)
  end
end
