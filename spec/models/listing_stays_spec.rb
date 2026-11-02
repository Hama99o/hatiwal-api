require "rails_helper"

RSpec.describe Listing, "stays" do
  let(:stays) { create(:category, slug: "stays-root", kind: Category::KIND_STAY) }
  let(:room_category) { create(:category, parent: stays) }
  let(:item_category) { create(:category) }

  it "defaults a stay to a price per night, and allows per month" do
    listing = create(:listing, category: room_category)
    expect(listing.price_unit).to eq(Listing::PRICE_UNIT_NIGHT)
    listing.update!(price_unit: Listing::PRICE_UNIT_MONTH)
    expect(listing.reload.price_unit).to eq("month")
  end

  it "keeps items on a total price: a unit is refused" do
    listing = build(:listing, category: item_category, price_unit: "night")
    expect(listing).not_to be_valid
    expect(listing.errors[:price_unit]).to be_present
  end

  it "lets Property rent be priced per month (not per night)" do
    rent = create(:category, slug: "apartments-rent")
    expect(build(:listing, category: rent, price_unit: "month")).to be_valid
    expect(build(:listing, category: rent, price_unit: "night")).not_to be_valid
  end

  it "stores a stay's details normalized and refuses bad ones" do
    listing = create(:listing, category: room_category, details: { "guests" => "2", "amenities" => [ "wifi" ] })
    expect(listing.reload.details).to eq("guests" => 2, "amenities" => [ "wifi" ])
    listing.details = { "guests" => 99 }
    expect(listing).not_to be_valid
    expect(listing.errors[:details].join).to include("guests must be")
  end

  it "refuses details on an item" do
    listing = build(:listing, category: item_category, details: { "guests" => 2 })
    expect(listing).not_to be_valid
    expect(listing.errors[:details]).to include("are only for stays")
  end

  it "drops the condition of a stay (a room has none)" do
    expect(create(:listing, category: room_category, condition: :good).condition).to be_nil
  end

  it "moving a stay to an item category drops its unit and details instead of failing" do
    listing = create(:listing, category: room_category, details: { "guests" => 2 })
    listing.update!(category: item_category)
    expect(listing.reload.price_unit).to be_nil
    expect(listing.details).to eq({})
  end

  describe "search scopes" do
    let!(:double) { create(:listing, :active, category: room_category, details: { "guests" => 2, "amenities" => %w[wifi breakfast] }) }
    let!(:family) { create(:listing, :active, category: room_category, details: { "guests" => 5, "amenities" => %w[wifi] }) }
    let!(:item) { create(:listing, :active, category: item_category) }

    it "finds rooms for at least N guests" do
      expect(Listing.for_guests(3)).to contain_exactly(family)
    end

    it "finds rooms with all the asked amenities" do
      expect(Listing.with_amenities(%w[wifi breakfast])).to contain_exactly(double)
    end

    it "filters by price unit" do
      expect(Listing.priced_per("night")).to contain_exactly(double, family)
    end
  end
end
