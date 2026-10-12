require "rails_helper"

# Hunt-2 (1.1.7): GET /listings?price_min=abc answered 500. A filter the client
# sent in a shape we cannot read is IGNORED, like an unknown `sort`: never a
# 500, and never a silently different result (abc must not become 0). This
# covers every numeric filter on the feed, with each kind of bad value: words,
# overflow ("1e999" is Infinity), NaN, arrays and hashes.
RSpec.describe "Api::V1::Listings with unreadable numeric filters", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  let!(:listing) { create(:listing, :active, title: "Kabul Lamp", price: 500, latitude: 34.5553, longitude: 69.2075) }

  def titles
    response.parsed_body["listings"].map { |l| l["title"] }
  end

  BAD_VALUES = [ "abc", "1e999", "-1e999", "NaN", "Infinity", "12abc", " " ].freeze

  %i[price_min price_max seller_active_days category_id user_id shop_id].each do |key|
    BAD_VALUES.each do |bad|
      it "ignores #{key}=#{bad.inspect}" do
        get "/api/v1/listings", params: { key => bad }, headers: headers
        expect(response).to have_http_status(:ok)
        expect(titles).to include("Kabul Lamp")
      end
    end

    it "ignores #{key} sent as an array or a hash" do
      get "/api/v1/listings", params: { key => [ "1", "2" ] }, headers: headers
      expect(response).to have_http_status(:ok)
      get "/api/v1/listings", params: { key => { "a" => "1" } }, headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "coordinates and radius" do
    BAD_VALUES.each do |bad|
      it "ignores the radius filter when one of them is #{bad.inspect}" do
        %i[latitude longitude radius].each do |key|
          params = { latitude: "34.5553", longitude: "69.2075", radius: "10" }.merge(key => bad)
          get "/api/v1/listings", params: params, headers: headers
          expect(response).to have_http_status(:ok), "#{key}=#{bad.inspect} → #{response.status}"
          expect(titles).to include("Kabul Lamp")
        end
      end

      it "sort=nearest with latitude=#{bad.inspect} falls back to newest" do
        get "/api/v1/listings", params: { sort: "nearest", latitude: bad, longitude: "69.2" }, headers: headers
        expect(response).to have_http_status(:ok)
        expect(titles).to include("Kabul Lamp")
      end
    end

    it "out-of-range coordinates are ignored, not a 500" do
      get "/api/v1/listings", params: { latitude: "999", longitude: "-999", radius: "10", sort: "nearest" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(titles).to include("Kabul Lamp")
    end
  end

  # Night QA on qa117 (dd, 2026-10-12): seller_active_days=99999999 answered
  # 500 (PG::DatetimeFieldOverflow: the cutoff became a date in 271765 BC), and
  # 0 or a negative count emptied the feed (a cutoff in the future). A count of
  # days outside 1..3650 means nothing, so it is ignored like the other
  # unreadable values. The apps only ever send 7.
  %w[99999999 999999999999 3651 0 -5].each do |days|
    it "ignores seller_active_days=#{days} (out of range)" do
      get "/api/v1/listings", params: { seller_active_days: days }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(titles).to include("Kabul Lamp")
    end
  end

  it "seller_active_days in range still filters" do
    listing.user.update_column(:last_sign_in_at, 30.days.ago)
    create(:listing, :active, title: "Fresh Seller Cup", user: create(:user, last_sign_in_at: 1.day.ago))
    get "/api/v1/listings", params: { seller_active_days: "7" }, headers: headers
    expect(titles).to eq([ "Fresh Seller Cup" ])
  end

  it "readable values still filter (the guard is not a no-op)" do
    create(:listing, :active, title: "Cheap Cup", price: 50)
    get "/api/v1/listings", params: { price_min: "100", price_max: "1000.5" }, headers: headers
    expect(titles).to eq([ "Kabul Lamp" ])
  end
end
