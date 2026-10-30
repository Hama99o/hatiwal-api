require "rails_helper"

# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md §1.3–1.4): ONE job decides
# each push — batched per search (6 h), capped per user (3 / local day), never
# in quiet hours (22:00–07:00 local), re-checked at send time, in the user's
# language. Every decision is one log line, ids only.
RSpec.describe SavedSearchAlertJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:buyer)    { create(:user, preferred_language: "en", push_token: "ExponentPushToken[buyer]") }
  let(:seller)   { create(:user) }
  let(:category) { create(:category, name_en: "Phones", name_ps: "موبایلونه", name_fa: "گوشی") }
  let!(:search)  { create(:saved_search, user: buyer, location: nil, alert: true, category: category, query: "iphone") } # before any match
  let(:pushes)   { [] }

  before do
    allow(Notifications::ExpoPushService).to receive(:deliver) do |**args|
      pushes << args
      Notifications::ExpoPushService::Result.new(ok: true, error: nil, details: nil)
    end
    allow(Rails.logger).to receive(:info).and_call_original
  end

  # Noon in Kabul (UTC+4:30) — outside quiet hours.
  around { |ex| travel_to(Time.utc(2026, 11, 2, 7, 30)) { ex.run } }

  def match!(title: "iPhone 12", price: 15_000)
    listing = create(:listing, :active, user: seller, category: category, title: title, price: price)
    SavedSearchMatchJob.perform_now(listing.id)
    listing
  end

  def logged(pattern) = have_received(:info).with(a_string_matching(pattern))

  it "pushes one match: the listing's title and price, in the user's language, deep-linking to the search" do
    match!
    described_class.perform_now(search.id)

    expect(pushes.size).to eq(1)
    expect(pushes.first[:title]).to eq("New match for «iphone»")
    expect(pushes.first[:body]).to include("iPhone 12")
    expect(pushes.first[:data]).to eq(type: "saved_search", savedSearchId: search.id)
    expect(search.reload).to have_attributes(pending_alert_count: 0, last_alerted_at: Time.current)
    expect(Rails.logger).to logged(/saved_search_alert event=sent saved_search_id=#{search.id} user_id=#{buyer.id} count=1/)
  end

  it "batches: three matches in the window make ONE push '3 new items'" do
    3.times { |i| match!(title: "iPhone #{i}") }
    described_class.perform_now(search.id)

    expect(pushes.size).to eq(1)
    expect(pushes.first[:title]).to eq("3 new items for «iphone»")
  end

  it "speaks Pashto and Dari (the label falls back to the category's own name)" do
    search.update!(query: nil)
    buyer.update!(preferred_language: "ps")
    match!
    described_class.perform_now(search.id)
    expect(pushes.last[:title]).to eq("نوی شی ستاسو د «موبایلونه» لټون لپاره")

    buyer.update!(preferred_language: "fa")
    travel 7.hours
    match!(title: "iPhone 13")
    described_class.perform_now(search.id)
    expect(pushes.last[:title]).to eq("مورد جدید برای جستجوی «گوشی»")
  end

  it "waits 6 hours after the last push of the same search (reschedules, does not drop)" do
    search.update!(last_alerted_at: 2.hours.ago)
    match!

    expect { described_class.perform_now(search.id) }.to have_enqueued_job(described_class).with(search.id).at(4.hours.from_now)
    expect(pushes).to be_empty
    expect(search.reload.pending_alert_count).to eq(1)
    expect(Rails.logger).to logged(/event=window saved_search_id=#{search.id}/)
  end

  it "sends at most 3 alert pushes per user per local day; the rest wait for the next morning" do
    buyer.update!(alert_pushes_on: Time.current.in_time_zone("Asia/Kabul").to_date, alert_pushes_count: 3)
    match!

    next_morning = Time.current.in_time_zone("Asia/Kabul").tomorrow.change(hour: 7)
    expect { described_class.perform_now(search.id) }.to have_enqueued_job(described_class).with(search.id).at(next_morning)
    expect(pushes).to be_empty
    expect(Rails.logger).to logged(/event=capped saved_search_id=#{search.id}/)
  end

  it "never pushes in quiet hours (22:00–07:00 local): rescheduled to 07:00" do
    travel_to(Time.utc(2026, 11, 2, 18, 0)) # 22:30 in Kabul
    match!

    morning = Time.utc(2026, 11, 3, 2, 30) # 07:00 in Kabul
    expect { described_class.perform_now(search.id) }.to have_enqueued_job(described_class).with(search.id).at(morning)
    expect(pushes).to be_empty
    expect(Rails.logger).to logged(/event=quiet saved_search_id=#{search.id}/)
  end

  it "uses the user's own clock: 22:20 in Karachi is quiet while Kabul is still at 21:50" do
    buyer.update!(province: "Sindh")
    expect(buyer.time_zone).to eq("Asia/Karachi")
    travel_to(Time.utc(2026, 11, 2, 17, 20))
    match!

    karachi_morning = Time.utc(2026, 11, 3, 2, 0) # 07:00 in Karachi (UTC+5)
    expect { described_class.perform_now(search.id) }.to have_enqueued_job(described_class).with(search.id).at(karachi_morning)
    expect(pushes).to be_empty
  end

  it "re-checks at send time: a listing sold since the match is never announced" do
    listing = match!
    listing.update!(status: :sold)

    described_class.perform_now(search.id)
    expect(pushes).to be_empty
    expect(search.reload.pending_alert_count).to eq(0)
    expect(Rails.logger).to logged(/event=stale saved_search_id=#{search.id}/)
  end

  it "sends nothing (and says so) when the user has no live push token" do
    buyer.update_columns(push_token: nil)
    match!

    described_class.perform_now(search.id)
    expect(pushes).to be_empty
    expect(Rails.logger).to logged(/event=no_token saved_search_id=#{search.id}/)
  end

  it "sends nothing once the alert is turned off" do
    match!
    search.update!(alert: false)

    described_class.perform_now(search.id)
    expect(pushes).to be_empty
  end
end
