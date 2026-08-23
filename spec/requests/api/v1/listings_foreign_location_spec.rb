require "rails_helper"

# A LOCATION OUTSIDE AFGHANISTAN MUST NOT BE BLOCKED.
#
# Hatiwal is a marketplace for Afghanistan, and the place SEARCH is deliberately
# scoped to it (`countrycodes=af` in the mobile app's utils/geocoding.ts). The
# mistake this guards against is scoping the whole feature that way — a seller
# travelling, or anyone whose GPS resolves abroad, must still be able to set a
# location and save a listing.
#
# WHY THIS LIVES HERE AND NOT ONLY IN MAESTRO.
# maestro/maps/map_location_outside_afghanistan.yaml drives the real picker, but
# it cannot prove the coordinate: `adb emu geo fix` is only delivered while an app
# is actively listening, and even with a fix pumped every 2s the app still fell
# back to DEFAULT_CENTER — a listing created by that flow saved 34.5553/69.2075,
# Kabul, while the flow passed. So the e2e flow proves "no refusal appears" and
# this spec proves "a foreign coordinate is actually accepted and returned".
# Neither half is sufficient alone, and the e2e half silently was not.
RSpec.describe "Api::V1::Listings with a location outside Afghanistan", type: :request do
  let(:seller)   { create(:user) }
  let(:headers)  { auth_headers_for(seller) }
  let(:category) { create(:category) }

  # Well outside any plausible Afghanistan bounding box (roughly 29..39 N, 60..75 E).
  PARIS  = { latitude: 48.8566, longitude: 2.3522 }.freeze
  SYDNEY = { latitude: -33.8688, longitude: 151.2093 }.freeze

  def create_listing(coords)
    post "/api/v1/my/listings",
         params: { listing: {
           title: "Abroad Location Item", price: 700, currency: "AFN",
           category_id: category.id, **coords
         } },
         headers: headers, as: :json
  end

  it "accepts a listing pinned in Paris and returns the coordinate unchanged" do
    create_listing(PARIS)

    expect(response).to have_http_status(:created)
    listing = Listing.find(JSON.parse(response.body).dig("listing", "id"))
    expect(listing.latitude.to_f).to be_within(0.0001).of(PARIS[:latitude])
    expect(listing.longitude.to_f).to be_within(0.0001).of(PARIS[:longitude])
  end

  it "accepts the southern hemisphere too — no sign assumptions" do
    # Afghanistan is entirely north and east of zero, so a negative latitude and a
    # longitude past 150 exercise a whole class of accidental bounds checks.
    create_listing(SYDNEY)

    expect(response).to have_http_status(:created)
    listing = Listing.order(:created_at).last
    expect(listing.latitude.to_f).to be_within(0.0001).of(SYDNEY[:latitude])
    expect(listing.longitude.to_f).to be_within(0.0001).of(SYDNEY[:longitude])
  end

  it "still rejects a coordinate that is not a real coordinate" do
    # "Not blocked by country" must not mean "not validated at all". Before the
    # matching validation was added to Listing, this returned 201 and persisted
    # latitude 91.0 — verified against the running API.
    create_listing(latitude: 91.0, longitude: 2.3522)

    expect(response).to have_http_status(:unprocessable_content)
    expect(Listing.where(title: "Abroad Location Item")).to be_empty
  end

  it "rejects an impossible longitude as well" do
    create_listing(latitude: 48.8566, longitude: 181.0)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
