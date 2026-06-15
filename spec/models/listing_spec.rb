require "rails_helper"

RSpec.describe Listing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:category) }
    it { should have_many(:conversations).dependent(:destroy) }
    it { should have_many(:saved_listings).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(150) }
    it { should validate_presence_of(:price) }
    it { should validate_numericality_of(:price).is_greater_than(0) }
    it { should validate_presence_of(:currency) }
    it { should validate_inclusion_of(:currency).in_array(%w[AFN USD EUR]) }
    it { should validate_presence_of(:category) }
  end

  describe "enums" do
    it { should define_enum_for(:status).with_values(draft: 0, active: 1, reserved: 2, sold: 3) }
    it {
      should define_enum_for(:condition)
        .with_values(brand_new: 0, like_new: 1, good: 2, fair: 3)
        .with_prefix(:condition)
    }
  end

  describe "scopes" do
    describe ".active" do
      it "returns only active listings" do
        active = create(:listing, :active)
        create(:listing, :draft)
        create(:listing, :sold)
        expect(Listing.active).to contain_exactly(active)
      end
    end

    describe ".ordered" do
      it "returns listings newest first" do
        old = create(:listing, created_at: 2.days.ago)
        newer = create(:listing, created_at: 1.hour.ago)
        expect(Listing.ordered.first).to eq(newer)
        expect(Listing.ordered.last).to eq(old)
      end
    end

    describe ".by_category" do
      it "returns listings in the given category" do
        category = create(:category)
        match    = create(:listing, category: category)
        create(:listing)
        expect(Listing.by_category(category.id)).to contain_exactly(match)
      end
    end

    describe ".by_seller" do
      it "returns listings owned by the given user" do
        seller = create(:user)
        match  = create(:listing, user: seller)
        create(:listing)
        expect(Listing.by_seller(seller.id)).to contain_exactly(match)
      end
    end

    describe ".browsable" do
      it "returns active listings newest first" do
        create(:listing, :draft)
        old_active = create(:listing, :active, created_at: 2.days.ago)
        new_active = create(:listing, :active, created_at: 1.hour.ago)
        expect(Listing.browsable.to_a).to eq([ new_active, old_active ])
      end
    end

    describe ".sorted" do
      let!(:cheap) { create(:listing, :active, price: 100, created_at: 2.days.ago) }
      let!(:expensive) { create(:listing, :active, price: 9000, created_at: 1.hour.ago) }

      it "sorts by price ascending for price_asc" do
        result = Listing.sorted("price_asc")
        expect(result.first).to eq(cheap)
        expect(result.last).to eq(expensive)
      end

      it "sorts by price descending for price_desc" do
        result = Listing.sorted("price_desc")
        expect(result.first).to eq(expensive)
        expect(result.last).to eq(cheap)
      end

      it "sorts newest first for newest" do
        result = Listing.sorted("newest")
        expect(result.first).to eq(expensive)
        expect(result.last).to eq(cheap)
      end

      it "sorts oldest first for oldest" do
        result = Listing.sorted("oldest")
        expect(result.first).to eq(cheap)
        expect(result.last).to eq(expensive)
      end

      it "falls back to newest for nil" do
        result = Listing.sorted(nil)
        expect(result.first).to eq(expensive)
      end

      it "falls back to newest for an unknown key" do
        result = Listing.sorted("unknown_sort")
        expect(result.first).to eq(expensive)
      end
    end
  end

  describe "timestamp callbacks" do
    it "sets published_at when becoming active" do
      listing = create(:listing, :draft)
      expect(listing.published_at).to be_nil
      listing.active!
      expect(listing.reload.published_at).to be_present
    end

    it "does not overwrite an existing published_at" do
      listing = create(:listing, :active)
      original = listing.published_at
      listing.update!(title: "Renamed")
      expect(listing.reload.published_at).to be_within(1.second).of(original)
    end

    it "sets reserved_at when becoming reserved" do
      listing = create(:listing, :active)
      listing.reserved!
      expect(listing.reload.reserved_at).to be_present
    end

    it "sets sold_at when becoming sold" do
      listing = create(:listing, :reserved)
      listing.sold!
      expect(listing.reload.sold_at).to be_present
    end
  end

  describe "image helpers" do
    let(:listing) { create(:listing) }

    describe "#thumbnail_url" do
      it "returns nil when no images attached" do
        expect(listing.thumbnail_url).to be_nil
      end
    end

    describe "#image_urls" do
      it "returns an empty array when no images attached" do
        expect(listing.image_urls).to eq([])
      end
    end
  end

  describe "CURRENCIES constant" do
    it "includes AFN, USD, and EUR" do
      expect(Listing::CURRENCIES).to contain_exactly("AFN", "USD", "EUR")
    end
  end

  describe "#thumbnail_url" do
    context "when no images are attached" do
      it "returns nil" do
        listing = create(:listing)
        expect(listing.thumbnail_url).to be_nil
      end
    end

    context "when images are attached" do
      it "returns an absolute URL starting with http" do
        ActiveStorage::Current.url_options = { host: "localhost", port: 3007, protocol: "http://" }
        listing = create(:listing, :with_image)
        expect(listing.thumbnail_url).to be_a(String)
        expect(listing.thumbnail_url).to start_with("http://")
      end
    end
  end

  describe "#image_urls" do
    it "returns empty array when no images" do
      listing = create(:listing)
      expect(listing.image_urls).to eq([])
    end

    it "returns array of absolute URLs when images attached" do
      ActiveStorage::Current.url_options = { host: "localhost", port: 3007, protocol: "http://" }
      listing = create(:listing, :with_image)
      expect(listing.image_urls).to be_an(Array)
      expect(listing.image_urls.first).to start_with("http://")
    end
  end

  describe ".search" do
    it "finds listings matching title" do
      phone = create(:listing, :active, title: "Samsung Galaxy Phone")
      create(:listing, :active, title: "Leather Jacket")
      expect(Listing.search("samsung")).to contain_exactly(phone)
    end

    it "supports multi-word search" do
      target = create(:listing, :active, title: "Samsung Galaxy Phone")
      create(:listing, :active, title: "Samsung Laptop")
      expect(Listing.search("samsung galaxy")).to contain_exactly(target)
    end

    it "returns all when blank" do
      create_list(:listing, 3, :active)
      expect(Listing.search("")).to match_array(Listing.all)
    end
  end
end
