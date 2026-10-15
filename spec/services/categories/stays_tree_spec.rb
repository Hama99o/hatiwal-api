require "rails_helper"

RSpec.describe Categories::StaysTree do
  it "creates the Stays tree with kind stay on every node" do
    described_class.apply!
    root = Category.find_by!(slug: "stays")
    expect(root.parent_id).to be_nil
    expect(root.subcategories.pluck(:slug)).to contain_exactly("hotel-rooms", "guest-houses", "bed-breakfast", "short-stay-apartments")
    expect(Category.where(slug: [ "stays" ] + root.subcategories.pluck(:slug)).pluck(:kind).uniq).to eq([ Category::KIND_STAY ])
    expect(root.name_ps).to eq("استوګنځایونه")
  end

  it "is idempotent" do
    described_class.apply!
    expect { described_class.apply! }.not_to change(Category, :count)
    expect(described_class.apply!).to eq(created: [], moved: [], kind_set: [])
  end

  it "moves the existing Property › Guest Houses (same row, its listings follow) without renaming it" do
    property = create(:category, slug: "property", position: 13)
    guest = create(:category, slug: "guest-houses", parent: property, name_ps: "مېلمه ځایونه")
    listing = create(:listing, :active, category: guest)

    result = described_class.apply!

    expect(result[:moved]).to eq([ "guest-houses" ])
    expect(guest.reload.parent.slug).to eq("stays")
    expect(guest.kind).to eq(Category::KIND_STAY)
    expect(guest.name_ps).to eq("مېلمه ځایونه")
    expect(listing.reload.category).to eq(guest)
    expect(Category.find_by!(slug: "stays").position).to eq(14)
  end
end
