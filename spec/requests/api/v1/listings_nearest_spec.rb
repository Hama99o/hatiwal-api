require "rails_helper"

# LOC-1 review — nearest-first is the DEFAULT Bazaar order (mobile + web), so:
#   * listings without a map point stay in the feed, after those with one;
#   * among those, the centre's province comes first, then newest;
#   * the boxed query returns exactly the same pages as the full sort;
#   * offset paging never repeats or skips a listing (id DESC tiebreak).
RSpec.describe "GET /api/v1/listings?sort=nearest", type: :request do
  let(:herat) { { latitude: 34.3529, longitude: 62.204 } }

  def feed(page: 1, size: 20, **extra)
    get "/api/v1/listings", params: { sort: "nearest", latitude: herat[:latitude], longitude: herat[:longitude],
                                      page: { number: page, size: size } }.merge(extra)
    body = JSON.parse(response.body)
    [ body["listings"].map { |l| l["id"] }, body["meta"]["pagination"] ]
  end

  it "orders by distance, then keeps listings without a point (centre's province first, then newest)" do
    near = create(:listing, :active, latitude: 34.36, longitude: 62.21, location: "Herat")
    far = create(:listing, :active, latitude: 34.5553, longitude: 69.2075, location: "Kabul")
    kabul_nopoint = create(:listing, :active, latitude: nil, longitude: nil, location: "Kabul, Afghanistan", created_at: 1.hour.ago)
    herat_nopoint_old = create(:listing, :active, latitude: nil, longitude: nil, location: "Herat, City Center", created_at: 2.days.ago)
    herat_nopoint_new = create(:listing, :active, latitude: nil, longitude: nil, location: "Herat", created_at: 1.day.ago)

    ids, meta = feed
    expect(ids).to eq([ near.id, far.id, herat_nopoint_new.id, herat_nopoint_old.id, kabul_nopoint.id ])
    expect(meta["total_count"]).to eq(5)
  end

  it "pages without duplicates or gaps, also for many listings at the same point" do
    25.times { create(:listing, :active, latitude: 34.36, longitude: 62.21) }
    5.times { create(:listing, :active, latitude: 34.5553, longitude: 69.2075) }
    3.times { create(:listing, :active, latitude: nil, longitude: nil) }

    pages = (1..4).map { |p| feed(page: p, size: 10).first }
    all = pages.flatten
    expect(all.size).to eq(33)
    expect(all.uniq.size).to eq(33)
    expect(feed(page: 1, size: 10).last["total_count"]).to eq(33)
  end

  it "returns the same pages as an unboxed sort" do
    create_list(:listing, 12, :active, latitude: 34.36, longitude: 62.21)
    create_list(:listing, 4, :active, latitude: 36.709, longitude: 67.11)
    create_list(:listing, 4, :active, latitude: 31.6133, longitude: 65.7101)
    full = Listing.browsable.nearest_first(herat[:latitude], herat[:longitude]).pluck(:id)

    pages = (1..4).map { |p| feed(page: p, size: 5).first }
    expect(pages.flatten).to eq(full)
  end

  it "still composes with a radius filter (the explicit Nearest chip with an area)" do
    inside = create(:listing, :active, latitude: 34.36, longitude: 62.21)
    create(:listing, :active, latitude: 34.5553, longitude: 69.2075)
    ids, = feed(radius: 20)
    expect(ids).to eq([ inside.id ])
  end
end

RSpec.describe Listing, ".nearest_window_km" do
  it "picks the smallest radius whose circle holds the page, or none" do
    create_list(:listing, 3, :active, latitude: 34.36, longitude: 62.21)
    create_list(:listing, 3, :active, latitude: 34.5553, longitude: 69.2075)
    scope = described_class.browsable.where.not(latitude: nil)
    expect(described_class.nearest_window_km(scope, 34.3529, 62.204, 3)).to eq(50)
    expect(described_class.nearest_window_km(scope, 34.3529, 62.204, 6)).to eq(1000)
    expect(described_class.nearest_window_km(scope, 34.3529, 62.204, 7)).to be_nil
  end

  it "uses the point index for the box" do
    sql = described_class.browsable.within_box(34.35, 62.2, 50).to_sql
    expect(sql).to include('"listings"."latitude" BETWEEN').and include('"listings"."longitude" BETWEEN')
  end
end
