require "rails_helper"

RSpec.describe "Listing takedown", type: :model do
  it "take_down! hides the listing from the buyer feed and records the reason" do
    listing = create(:listing, :active)
    expect(Listing.browsable).to include(listing)

    listing.take_down!(reason: "Prohibited item")

    expect(listing.removed?).to be(true)
    expect(listing.removed_reason).to eq("Prohibited item")
    expect(Listing.browsable).not_to include(listing)
  end

  it "restore! returns the listing to the feed" do
    listing = create(:listing, :active)
    listing.take_down!

    listing.restore!

    expect(listing.removed?).to be(false)
    expect(listing.removed_reason).to be_nil
    expect(Listing.browsable).to include(listing)
  end
end
