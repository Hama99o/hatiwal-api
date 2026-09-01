require "rails_helper"

# SAFETY-1 — a public listing must not publish the seller's front door.
#
# These specs pin the PROPERTY that matters (the published point is coarse and
# irreversible), not the arithmetic. A test that just re-implements the rounding
# would pass even if the grid were made uselessly fine.
RSpec.describe Listing, "location privacy" do
  # Kabul, six decimals — the precision the column actually stores and the API
  # actually shipped.
  let(:lat) { 34.526950 }
  let(:lng) { 69.185058 }
  let(:listing) { create(:listing, latitude: lat, longitude: lng) }

  describe "#approximate_latitude / #approximate_longitude" do
    it "moves the published point off the true one" do
      expect(listing.approximate_latitude.to_f).not_to eq(lat)
      expect(listing.approximate_longitude.to_f).not_to eq(lng)
    end

    it "stays close enough to be useful — within ~400m of the truth" do
      # The buyer's real question is "which part of town", so the point must not
      # wander into the next district.
      dlat_m = (listing.approximate_latitude.to_f - lat).abs * 111_320
      dlng_m = (listing.approximate_longitude.to_f - lng).abs * 111_320 *
               Math.cos(lat * Math::PI / 180)
      expect(Math.sqrt((dlat_m**2) + (dlng_m**2))).to be < 400
    end

    it "is STABLE — the same listing publishes the same point every time" do
      # A value that moved per request would let an attacker average many
      # samples back to the true coordinate.
      expect(listing.approximate_latitude).to eq(listing.reload.approximate_latitude)
      expect(listing.approximate_longitude).to eq(listing.reload.approximate_longitude)
    end

    it "COLLAPSES nearby listings onto one point, so the original is unrecoverable" do
      # This is the property a pseudo-random offset cannot give: two different
      # true points inside a cell publish the SAME coordinate, so knowing the
      # algorithm reveals nothing about which one it was. Irreversible by
      # construction.
      near = create(:listing, latitude: lat + 0.0004, longitude: lng + 0.0004)
      expect(near.approximate_latitude).to eq(listing.approximate_latitude)
      expect(near.approximate_longitude).to eq(listing.approximate_longitude)
    end

    it "returns nil for a listing with no coordinates" do
      # Never invent a phantom point at 0,0 in the Atlantic.
      blank = build(:listing, latitude: nil, longitude: nil)
      expect(blank.approximate_latitude).to be_nil
      expect(blank.approximate_longitude).to be_nil
    end
  end

  describe "serialization" do
    it "the PUBLIC :detailed view never carries the exact coordinate" do
      json = JSON.parse(ListingSerializer.render(listing, view: :detailed))
      expect(json["latitude"].to_f).not_to eq(lat)
      expect(json["longitude"].to_f).not_to eq(lng)
      expect(json["latitude"].to_f).to eq(listing.approximate_latitude.to_f)
      # The client is TOLD it is approximate, so it can draw an area not a pin.
      expect(json["location_precision"]).to eq("approximate")
      expect(json["location_radius_m"]).to eq(Listing::APPROXIMATE_LOCATION_RADIUS_M)
    end

    it "the OWNER's :owner_detailed view keeps the exact coordinate" do
      # Otherwise the seller's own edit form would load a snapped point and save
      # it back, destroying the real one.
      json = JSON.parse(ListingSerializer.render(listing, view: :owner_detailed))
      expect(json["latitude"].to_f).to eq(lat)
      expect(json["longitude"].to_f).to eq(lng)
      expect(json["location_precision"]).to eq("exact")
      expect(json["location_radius_m"]).to be_nil
    end

    it "the :list view carries no coordinates at all" do
      json = JSON.parse(ListingSerializer.render(listing, view: :list))
      expect(json).not_to have_key("latitude")
      expect(json).not_to have_key("longitude")
    end
  end
end
