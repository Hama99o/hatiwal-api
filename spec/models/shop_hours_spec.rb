require "rails_helper"

# SHOP-1 review — open now / next change, decided on the server in the shop's
# own time zone (Asia/Kabul; Asia/Karachi for Pakistan), overnight ranges allowed.
RSpec.describe Shop, "opening hours" do
  # 2026-10-09 is a Friday; 2026-10-10 a Saturday.
  def kabul(str) = ActiveSupport::TimeZone["Asia/Kabul"].parse(str)

  let(:sat_thu) { %w[sat sun mon tue wed thu].index_with { [ %w[08:00 18:00] ] }.merge("fri" => []) }
  let(:shop) { create(:shop, hours: sat_thu) }

  it "is closed all Friday and opens Saturday 08:00" do
    friday_noon = kabul("2026-10-09 12:00")
    expect(shop.open_now(at: friday_noon)).to be(false)
    expect(shop.next_change_at(at: friday_noon)).to eq(kabul("2026-10-10 08:00"))
  end

  it "is open on a Saturday morning until 18:00" do
    expect(shop.open_now(at: kabul("2026-10-10 09:30"))).to be(true)
    expect(shop.next_change_at(at: kabul("2026-10-10 09:30"))).to eq(kabul("2026-10-10 18:00"))
  end

  it "uses Kabul time, not UTC, at the boundary" do
    # 07:45 Kabul = 03:15 UTC: still closed. 08:00 Kabul = 03:30 UTC: open.
    expect(shop.open_now(at: Time.utc(2026, 10, 10, 3, 15))).to be(false)
    expect(shop.open_now(at: Time.utc(2026, 10, 10, 3, 30))).to be(true)
  end

  it "accepts an overnight range and is open after midnight on the next day" do
    night = create(:shop, hours: { "fri" => [ %w[18:00 02:00] ] })
    expect(night).to be_valid
    expect(night.open_now(at: kabul("2026-10-09 23:00"))).to be(true)
    expect(night.open_now(at: kabul("2026-10-10 01:30"))).to be(true)
    expect(night.next_change_at(at: kabul("2026-10-10 01:30"))).to eq(kabul("2026-10-10 02:00"))
    expect(night.open_now(at: kabul("2026-10-10 02:30"))).to be(false)
  end

  it "refuses a range that starts and ends at the same time" do
    expect(build(:shop, hours: { "sat" => [ %w[08:00 08:00] ] })).not_to be_valid
  end

  it "says nothing when the shop states no hours" do
    open_ended = create(:shop, hours: {})
    expect(open_ended.open_now).to be_nil
    expect(open_ended.next_change_at).to be_nil
  end

  it "keeps Pakistani shops on Pakistan time" do
    lahore = create(:shop, latitude: 31.55, longitude: 74.34, hours: sat_thu)
    expect(lahore.province).to eq("Punjab")
    expect(lahore.time_zone).to eq("Asia/Karachi")
  end

  it "takes the province from the pin, whatever was typed" do
    expect(create(:shop, province: "Kabul", latitude: 34.36, longitude: 62.21).province).to eq("Herat")
  end
end
