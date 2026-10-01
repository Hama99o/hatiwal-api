require "rails_helper"

RSpec.describe Admin::GrowthSeries do
  include ActiveSupport::Testing::TimeHelpers

  around { |ex| travel_to(Time.utc(2026, 9, 20, 12)) { ex.run } }

  # Friday 2026-09-04 21:00 UTC is Saturday 2026-09-05 01:30 in Kabul (UTC+04:30),
  # so it belongs to the week starting SATURDAY 09-05, not the one before.
  it "buckets weeks on Kabul time, starting on Saturday" do
    create(:user, created_at: Time.utc(2026, 9, 4, 21, 0))  # Kabul: Sat 01:30
    create(:user, created_at: Time.utc(2026, 9, 4, 19, 0))  # Kabul: Fri 23:30

    series = described_class.for(User.members, "week")

    expect(series[Date.new(2026, 9, 5)]).to eq(1)  # the Saturday week
    expect(series[Date.new(2026, 8, 29)]).to eq(1) # the Saturday before
    expect(series.keys).to all(satisfy(&:saturday?))
  end

  # 2026-08-31 21:00 UTC is already 1 September in Kabul.
  it "puts a late-night signup on the Kabul month, not the UTC one" do
    create(:user, created_at: Time.utc(2026, 8, 31, 21, 0))

    series = described_class.for(User.members, "month")

    expect(series[Date.new(2026, 9, 1)]).to eq(1)
    expect(series[Date.new(2026, 8, 1)]).to eq(0)
  end

  it "returns every bucket, zeros included, for each period" do
    expect(described_class.for(User.members, "week").size).to eq(12)
    expect(described_class.for(User.members, "month").size).to eq(12)
    expect(described_class.for(User.members, "year").size).to eq(5)
  end

  it "falls back to weekly for an unknown period" do
    expect(described_class.normalize("decade")).to eq("week")
    expect(described_class.normalize(nil)).to eq("week")
  end

  it "does not count the Support account as a new user" do
    User.support_account!
    create(:user)

    expect(described_class.for(User.members, "year").values.sum).to eq(1)
  end
end
