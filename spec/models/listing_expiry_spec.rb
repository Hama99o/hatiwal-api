require "rails_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): expiry stays, but
# never hurts the seller — 90 days, Renew never moves the listing, an edit +
# relaunch may bump it at most once a week, reminders 7 days and 1 day before.
RSpec.describe Listing, "expiry (90 days)", type: :model do
  include ActiveSupport::Testing::TimeHelpers
  let(:seller) { create(:user) }

  it "runs 90 days from publishing" do
    draft = create(:listing, :draft, :with_image, user: seller)
    freeze_time do
      expect(draft.publish).to be(true)
      expect(draft.reload.expires_at).to eq(90.days.from_now)
    end
  end

  describe "#renew!" do
    it "gives 90 days from now and never moves the listing in the feed" do
      listing = create(:listing, :active, user: seller, created_at: 100.days.ago, expires_at: 10.days.ago)
      bumped_at = listing.bumped_at

      freeze_time do
        listing.renew!
        expect(listing.reload.expires_at).to eq(90.days.from_now)
        expect(listing.bumped_at).to eq(bumped_at)
      end
    end
  end

  describe "#relaunch!" do
    it "renews AND moves the listing to the top when it has not been bumped for a week" do
      listing = create(:listing, :active, user: seller, created_at: 100.days.ago, expires_at: 10.days.ago)

      freeze_time do
        expect(listing.relaunch!).to be(true)
        expect(listing.reload.bumped_at).to eq(Time.current)
        expect(listing.expires_at).to eq(90.days.from_now)
        expect(listing.next_bump_at).to eq(7.days.from_now)
      end
    end

    it "renews but does not bump again within the week" do
      listing = create(:listing, :active, user: seller, created_at: 100.days.ago)
      listing.relaunch!
      first_bump = listing.reload.bumped_at

      travel 3.days do
        expect(listing.relaunch!).to be(false)
        expect(listing.reload.bumped_at).to eq(first_bump)
        expect(listing.expires_at).to be_within(1.second).of(90.days.from_now)
      end

      travel 7.days + 1.second do
        expect(listing.relaunch!).to be(true)
      end
    end
  end

  describe "feed order" do
    it "starts at creation, so the newest-first order is unchanged" do
      listing = create(:listing, :active, user: seller, created_at: 5.days.ago)
      expect(listing.reload.bumped_at).to be_within(1.second).of(5.days.ago)
    end

    it "puts a relaunched listing first; a renewed one stays where it was" do
      newest  = create(:listing, :active, user: seller, created_at: 1.day.ago)
      renewed = create(:listing, :active, user: seller, created_at: 20.days.ago)
      relaunched = create(:listing, :active, user: seller, created_at: 30.days.ago)

      renewed.renew!
      relaunched.relaunch!

      expect(Listing.browsable.to_a).to eq([ relaunched, newest, renewed ])
      expect(Listing.browsable.sorted("newest").to_a).to eq([ relaunched, newest, renewed ])
    end
  end

  describe ".expiry_reminder_due" do
    it "finds live listings inside the window, once per expiry" do
      week = create(:listing, :active, user: seller, expires_at: 6.days.from_now)
      day  = create(:listing, :reserved, user: seller, expires_at: 20.hours.from_now)
      far  = create(:listing, :active, user: seller, expires_at: 30.days.from_now)
      gone = create(:listing, :active, user: seller, expires_at: 1.hour.ago)
      sold = create(:listing, :sold, user: seller, expires_at: 2.days.from_now)

      expect(described_class.expiry_reminder_due(:week)).to contain_exactly(week, day)
      expect(described_class.expiry_reminder_due(:day)).to contain_exactly(day)
      expect(described_class.expiry_reminder_due(:week)).not_to include(far, gone, sold)

      week.update_column(:expiry_reminder_week_for, week.expires_at)
      expect(described_class.expiry_reminder_due(:week)).not_to include(week)

      # A renew re-arms it for the new expiry.
      week.update_column(:expires_at, 3.days.from_now)
      expect(described_class.expiry_reminder_due(:week)).to include(week)
    end
  end

  describe "data migration: existing live listings get 90 days from creation" do
    require Rails.root.join("db/migrate/20261007130100_extend_live_listings_to_ninety_days")

    it "extends, never shortens, is idempotent, and leaves drafts/sold/no-expiry alone" do
      created = 20.days.ago
      short   = create(:listing, :active, user: seller, created_at: created, expires_at: created + 30.days)
      held    = create(:listing, :reserved, user: seller, created_at: created, expires_at: created + 30.days)
      later   = create(:listing, :active, user: seller, created_at: created, expires_at: created + 120.days)
      old     = create(:listing, :active, user: seller, created_at: 100.days.ago, expires_at: 70.days.ago)
      never   = create(:listing, :active, user: seller, created_at: created, expires_at: nil)
      sold    = create(:listing, :sold, user: seller, created_at: created, expires_at: created + 30.days)

      migration = ExtendLiveListingsToNinetyDays.new
      migration.verbose = false
      2.times { migration.up }

      expect(short.reload.expires_at).to be_within(1.second).of(created + 90.days)
      expect(held.reload.expires_at).to be_within(1.second).of(created + 90.days)
      expect(later.reload.expires_at).to be_within(1.second).of(created + 120.days)
      expect(old.reload.expires_at).to be_within(1.second).of(10.days.ago)
      expect(old).to be_expired
      expect(never.reload.expires_at).to be_nil
      expect(sold.reload.expires_at).to be_within(1.second).of(created + 30.days)
    end
  end
end
