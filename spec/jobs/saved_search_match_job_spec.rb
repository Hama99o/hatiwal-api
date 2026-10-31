require "rails_helper"

# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §1.2): a listing that goes
# live is matched against FOLLOWED searches only, once per (search, listing),
# and each match is only counted — the push is decided later (§1.3).
RSpec.describe SavedSearchMatchJob, type: :job do
  include ActiveJob::TestHelper

  let(:buyer)    { create(:user) }
  let(:seller)   { create(:user) }
  let(:category) { create(:category) }
  let(:listing)  { create(:listing, :active, user: seller, category: category, title: "iPhone 12", price: 15_000) }

  def follow(**attrs)
    create(:saved_search, user: buyer, location: nil, alert: true, **attrs)
  end

  it "counts a match on a followed search and schedules its alert" do
    search = follow(category: category, query: "iphone")

    expect { described_class.perform_now(listing.id) }.to have_enqueued_job(SavedSearchAlertJob).with(search.id)
    expect(search.reload.pending_alert_count).to eq(1)
    expect(SavedSearchAlertHit.where(saved_search: search, listing: listing).count).to eq(1)
  end

  it "ignores the auto-saved history (alert off)" do
    search = create(:saved_search, user: buyer, location: nil, category: category)

    described_class.perform_now(listing.id)
    expect(search.reload.pending_alert_count).to eq(0)
  end

  it "ignores a user who turned every alert off" do
    buyer.update!(saved_search_alerts: false)
    search = follow(category: category)

    described_class.perform_now(listing.id)
    expect(search.reload.pending_alert_count).to eq(0)
  end

  it "counts a listing once per search, however many times it goes live" do
    search = follow(category: category)

    2.times { described_class.perform_now(listing.id) }
    expect(search.reload.pending_alert_count).to eq(1)
  end

  it "does nothing for a search that does not match, or the seller's own" do
    other = follow(query: "samsung")
    own   = create(:saved_search, user: seller, location: nil, alert: true)

    described_class.perform_now(listing.id)
    expect([ other.reload.pending_alert_count, own.reload.pending_alert_count ]).to eq([ 0, 0 ])
  end

  it "is enqueued when a listing goes live (publish), not on an ordinary edit" do
    draft = create(:listing, :with_image, user: seller, category: category)

    expect { draft.update!(status: :active) }.to have_enqueued_job(described_class).with(draft.id)
    expect { draft.update!(price: 9_000) }.not_to have_enqueued_job(described_class)
  end
end
