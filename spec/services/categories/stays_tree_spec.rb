require "rails_helper"

RSpec.describe Categories::StaysTree do
  it "creates the Stays root and its own subcategories, kind stay on every node" do
    described_class.apply!
    root = Category.find_by!(slug: "stays")
    expect(root.parent_id).to be_nil
    expect(root.subcategories.pluck(:slug)).to contain_exactly("hotel-rooms", "bed-breakfast", "short-stay-apartments")
    expect(Category.where(slug: [ "stays" ] + root.subcategories.pluck(:slug)).pluck(:kind).uniq).to eq([ Category::KIND_STAY ])
    expect(root.name_ps).to eq("استوګنځایونه")
  end

  it "is idempotent" do
    described_class.apply!
    expect { described_class.apply! }.not_to change(Category, :count)
    expect(described_class.apply!).to eq(created: [], kind_set: [])
  end

  it "apply! alone never touches Property › Guest Houses (the move is its own step)" do
    property = create(:category, slug: "property")
    guest = create(:category, slug: "guest-houses", parent: property)
    described_class.apply!
    expect(guest.reload.parent).to eq(property)
    expect(guest.kind).to eq(Category::KIND_ITEM)
  end

  describe "Guest Houses (option A, reversible)" do
    let!(:property) { create(:category, slug: "property", position: 13) }
    let!(:guest) { create(:category, slug: "guest-houses", parent: property, name_ps: "مېلمه ځایونه") }
    let!(:listing) { create(:listing, :active, category: guest) }

    before { described_class.apply! }

    it "moves the same row under Stays (its listings follow, its names stay)" do
      expect(described_class.move_guest_houses!).to eq(created: false, moved: true)
      expect(guest.reload.parent.slug).to eq("stays")
      expect(guest.kind).to eq(Category::KIND_STAY)
      expect(guest.name_ps).to eq("مېلمه ځایونه")
      expect(listing.reload.category).to eq(guest)
      expect(Category.find_by!(slug: "stays").position).to eq(14)
    end

    it "restores it under Property as an item (option B / rollback)" do
      described_class.move_guest_houses!
      expect(described_class.restore_guest_houses!).to eq(restored: true)
      expect(guest.reload.parent).to eq(property)
      expect(guest.kind).to eq(Category::KIND_ITEM)
      expect(listing.reload.category).to eq(guest)
    end
  end

  it "creates Guest Houses under Stays on a fresh database" do
    described_class.apply!
    expect(described_class.move_guest_houses!).to eq(created: true, moved: false)
    expect(Category.find_by!(slug: "guest-houses").parent.slug).to eq("stays")
  end

  it "remove! drops the empty Stays categories and keeps any that hold a listing" do
    described_class.apply!
    create(:listing, category: Category.find_by!(slug: "hotel-rooms"))
    expect(described_class.remove!).to eq(kept: [ "hotel-rooms", "stays" ])
    expect(Category.where(slug: %w[bed-breakfast short-stay-apartments])).to be_empty
  end
end
