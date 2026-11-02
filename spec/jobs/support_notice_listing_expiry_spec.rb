require "rails_helper"

# The Support half of the listing expiry reminders (ListingExpiryReminderJob):
# in the seller's language, no second push (the reminder job pushes), and only
# while the listing is still live, theirs, and on the same expiry.
RSpec.describe SupportNoticeJob, "listing expiry notices", type: :job do
  include ActiveJob::TestHelper

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  let(:seller)  { create(:user, firstname: "Gul", preferred_language: "fa") }
  let(:listing) { create(:listing, :active, user: seller, title: "Bike", expires_at: 6.days.from_now) }

  def payload(l = listing) = { "listing_id" => l.id, "expires_at" => l.expires_at.iso8601(6) }
  def person_notices = Conversation.kind_support.where(buyer_id: seller.id, shop_id: nil).flat_map(&:messages)

  it "posts the reminder in the seller's language, without a second push" do
    expect { described_class.perform_now(seller.id, "listing_expires_week", nil, payload) }
      .to have_enqueued_job(BroadcastMessageJob)
    expect(SendMessagePushJob).not_to have_been_enqueued

    expect(person_notices.sole.body)
      .to eq(I18n.t("support.notices.listing_expires_week", locale: :fa, name: "Gul", title: "Bike"))
  end

  it "enqueues with the listing's shop and expiry" do
    expect { described_class.enqueue(seller, :listing_expires_day, listing: listing) }
      .to have_enqueued_job(described_class).with(seller.id, "listing_expires_day", nil, payload)
  end

  it "says nothing once the listing was renewed, sold or removed" do
    renewed = payload
    listing.renew!
    described_class.perform_now(seller.id, "listing_expires_week", nil, renewed)

    sold = create(:listing, :sold, user: seller, expires_at: 6.days.from_now)
    described_class.perform_now(seller.id, "listing_expires_week", nil, payload(sold))

    removed = create(:listing, :active, user: seller, expires_at: 6.days.from_now, removed_at: Time.current)
    described_class.perform_now(seller.id, "listing_expires_week", nil, payload(removed))

    expect(person_notices).to be_empty
  end

  it "every locale has both texts" do
    %i[en ps fa ur].each do |locale|
      %w[listing_expires_week listing_expires_day].each do |key|
        expect(I18n.t("support.notices.#{key}", locale: locale, name: "x", title: "y", raise: true)).to include("y")
      end
    end
  end
end
