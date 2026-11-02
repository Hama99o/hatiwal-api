require "rails_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): 7 days and 1 day
# before expiry, a push (opens the listing, with Renew) + the seller's Support
# notice, in their language, once per listing per expiry.
RSpec.describe ListingExpiryReminderJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:seller) { create(:user, preferred_language: "ps", push_token: "ExponentPushToken[abc]") }
  let(:ok)     { Notifications::ExpoPushService::Result.new(ok: true, error: nil, details: nil) }

  before { allow(Notifications::ExpoPushService).to receive(:deliver).and_return(ok) }

  it "sends the 7-day reminder: a push that opens the listing, and the Support notice" do
    listing = create(:listing, :active, user: seller, title: "Bike", expires_at: 6.days.from_now)

    expect { described_class.perform_now }
      .to have_enqueued_job(SupportNoticeJob).with(seller.id, "listing_expires_week", nil, hash_including("listing_id" => listing.id))

    expect(Notifications::ExpoPushService).to have_received(:deliver).with(
      token: "ExponentPushToken[abc]",
      title: I18n.t("push.listing_expiry.week_title", locale: :ps),
      body: I18n.t("push.listing_expiry.body", locale: :ps, title: "Bike"),
      data: { type: "listing_expiry", listingId: listing.id, shopId: nil, reminder: "week" }
    )
    expect(listing.reload.expiry_reminder_week_for).to eq(listing.expires_at)
  end

  it "sends each reminder once per expiry, however often it runs" do
    create(:listing, :active, user: seller, expires_at: 6.days.from_now)

    3.times { described_class.perform_now }

    expect(Notifications::ExpoPushService).to have_received(:deliver).once
    expect(enqueued_jobs.count { |j| j["job_class"] == "SupportNoticeJob" }).to eq(1)
  end

  it "then the 1-day reminder, separately" do
    listing = create(:listing, :active, user: seller, expires_at: 6.days.from_now)
    described_class.perform_now

    travel 5.days + 12.hours do
      described_class.perform_now
    end

    expect(Notifications::ExpoPushService).to have_received(:deliver).twice
    expect(Notifications::ExpoPushService).to have_received(:deliver)
      .with(hash_including(data: { type: "listing_expiry", listingId: listing.id, shopId: nil, reminder: "day" }))
  end

  it "a listing first seen inside the last day gets only the 1-day reminder" do
    listing = create(:listing, :active, user: seller, expires_at: 10.hours.from_now)

    described_class.perform_now

    expect(Notifications::ExpoPushService).to have_received(:deliver).once
    expect(listing.reload.expiry_reminder_week_for).to eq(listing.expires_at)
    expect(listing.expiry_reminder_day_for).to eq(listing.expires_at)
  end

  it "re-arms after a renew" do
    listing = create(:listing, :active, user: seller, expires_at: 6.days.from_now)
    described_class.perform_now

    listing.renew!
    travel 84.days do
      described_class.perform_now
    end

    expect(Notifications::ExpoPushService).to have_received(:deliver).twice
  end

  it "says nothing about listings far from expiry, already expired, sold, drafts or removed" do
    create(:listing, :active, user: seller, expires_at: 30.days.from_now)
    create(:listing, :active, user: seller, expires_at: 1.hour.ago)
    create(:listing, :sold, user: seller, expires_at: 2.days.from_now)
    create(:listing, :draft, user: seller, expires_at: 2.days.from_now)
    create(:listing, :active, user: seller, expires_at: 2.days.from_now, removed_at: Time.current)

    expect { described_class.perform_now }.not_to have_enqueued_job(SupportNoticeJob)
    expect(Notifications::ExpoPushService).not_to have_received(:deliver)
  end

  it "still sends the Support notice when the seller has no push token" do
    seller.update_column(:push_token, nil)
    create(:listing, :active, user: seller, expires_at: 6.days.from_now)

    expect { described_class.perform_now }.to have_enqueued_job(SupportNoticeJob)
    expect(Notifications::ExpoPushService).not_to have_received(:deliver)
  end

  it "drops a token the device no longer accepts" do
    allow(Notifications::ExpoPushService).to receive(:deliver)
      .and_return(Notifications::ExpoPushService::Result.new(ok: false, error: "DeviceNotRegistered", details: nil))
    create(:listing, :active, user: seller, expires_at: 6.days.from_now)

    described_class.perform_now

    expect(seller.reload.push_token).to be_nil
  end

  it "a shop product: tells its poster, with the shop for the Support thread" do
    shop = create(:shop, owner: seller)
    listing = create(:listing, :active, user: seller, shop: shop, expires_at: 6.days.from_now)

    expect { described_class.perform_now }
      .to have_enqueued_job(SupportNoticeJob).with(seller.id, "listing_expires_week", shop.id, hash_including("listing_id" => listing.id))
    # The push names the shop, so the app opens it as that shop, in Seller mode.
    expect(Notifications::ExpoPushService).to have_received(:deliver)
      .with(hash_including(data: hash_including(type: "listing_expiry", listingId: listing.id, shopId: shop.id)))
  end
end
