require "rails_helper"

# Edge-case pass, 2026-10-08 — listing expiry (90 days, reminders, renew).
RSpec.describe "Listing expiry — edge cases", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:seller) { create(:user, :confirmed) }
  let(:headers) { seller.create_new_auth_token }
  let(:published_at) { Time.zone.parse("2026-01-01 10:00") }
  let!(:listing) do
    travel_to(published_at) { create(:listing, :active, user: seller, expires_at: Listing::LISTING_LIFESPAN.from_now) }
  end

  def on_day(day, &) = travel_to(published_at + day.days, &)

  describe "day 89 / 90 / 91" do
    it "day 89: live, in the feed, not in Expired" do
      on_day(89) do
        expect(listing.reload.expired?).to be(false)
        expect(Listing.browsable).to include(listing)
        expect(Listing.expired_active).not_to include(listing)
      end
    end

    it "day 90, the exact instant: expired everywhere at once (the model agrees with the scopes)" do
      on_day(90) do
        expect(Listing.browsable).not_to include(listing)
        expect(Listing.expired_active).to include(listing)
        expect(listing.reload.expired?).to be(true)
      end
    end

    it "day 91: expired; renew brings it back for a full 90 days from NOW (not from the old expiry)" do
      on_day(91) do
        put "/api/v1/my/listings/#{listing.id}/renew", headers: headers
        expect(response).to have_http_status(:ok)
        expect(listing.reload.expires_at).to be_within(1.second).of(90.days.from_now)
        expect(Listing.browsable).to include(listing)
      end
    end

    it "day 89: an early renew restarts the 90 days (does not stack)" do
      on_day(89) do
        put "/api/v1/my/listings/#{listing.id}/renew", headers: headers
        expect(listing.reload.expires_at).to be_within(1.second).of(90.days.from_now)
      end
    end
  end

  describe "renewing what can't be renewed" do
    it "a sold listing is refused" do
      listing.update_columns(status: Listing.statuses[:sold])
      put "/api/v1/my/listings/#{listing.id}/renew", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "a deleted listing is refused, and stays deleted and out of the feed" do
      on_day(91) do
        listing.update!(removed_at: Time.current, removed_reason: "deleted_by_seller")
        before = listing.reload.expires_at
        put "/api/v1/my/listings/#{listing.id}/renew", headers: headers
        expect(response).to have_http_status(:forbidden)
        put "/api/v1/my/listings/#{listing.id}/relaunch", headers: headers
        expect(response).to have_http_status(:forbidden)
        expect(listing.reload.expires_at).to eq(before)
        expect(Listing.browsable).not_to include(listing)
      end
    end

    it "Relaunch all skips deleted and sold listings" do
      gone = create(:listing, :expired, user: seller, removed_at: Time.current)
      sold = create(:listing, :sold, user: seller, expires_at: 1.day.ago)
      on_day(91) do
        post "/api/v1/my/listings/relaunch_expired", params: {}, headers: headers, as: :json
        expect(response.parsed_body).to eq("renewed" => 1, "failed" => 0)
      end
      expect([ gone.reload.expires_at, sold.reload.expires_at ]).to all(be < Time.current)
    end
  end

  describe "reminders" do
    it "are not sent twice, even by two overlapping runs, and re-arm after a renew" do
      seller.update_columns(push_token: "ExponentPushToken[x]")
      allow(Notifications::ExpoPushService).to receive(:deliver).and_return(double(error: nil))
      on_day(84) { 2.times { ListingExpiryReminderJob.perform_now } }
      on_day(89) { 2.times { ListingExpiryReminderJob.perform_now } }
      expect(Notifications::ExpoPushService).to have_received(:deliver).twice # week + day, once each
      on_day(89) { listing.renew! }
      on_day(89 + 84) { ListingExpiryReminderJob.perform_now }
      expect(Notifications::ExpoPushService).to have_received(:deliver).exactly(3).times
    end

    it "use absolute instants: the result is the same whatever the server's time zone" do
      seller.update_columns(push_token: "ExponentPushToken[x]")
      allow(Notifications::ExpoPushService).to receive(:deliver).and_return(double(error: nil))
      Time.use_zone("Asia/Kabul") { on_day(89) { ListingExpiryReminderJob.perform_now } }
      expect(Notifications::ExpoPushService).to have_received(:deliver).once
    end
  end

  describe "moving or duplicating an expired listing" do
    let(:shop) { create(:shop, owner: seller) }

    it "a duplicate is a fresh draft: no expiry, no reminder marks; the original stays expired" do
      on_day(91) do
        post "/api/v1/my/listings/#{listing.id}/duplicate", headers: headers, params: { shop_id: nil }, as: :json
        expect(response).to have_http_status(:created).or have_http_status(:ok)
        copy = Listing.order(:id).last
        expect(copy).to be_draft
        expect([ copy.expires_at, copy.expiry_reminder_week_for, copy.expiry_reminder_day_for ]).to eq([ nil, nil, nil ])
        expect(listing.reload.expired?).to be(true)
      end
    end

    it "a move keeps the expiry as it was (the seller renews it from its new place)" do
      on_day(91) do
        before = listing.expires_at
        put "/api/v1/my/listings/#{listing.id}/move", headers: headers, params: { shop_id: shop.id }, as: :json
        expect(response).to have_http_status(:ok)
        expect(listing.reload.shop_id).to eq(shop.id)
        expect(listing.expires_at).to eq(before)
        expect(Listing.expired_active.where(shop_id: shop.id)).to include(listing)
      end
    end
  end
end
