require "rails_helper"

RSpec.describe Listing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:category) }
    it { should have_many(:conversations).dependent(:destroy) }
    it { should have_many(:saved_listings).dependent(:destroy) }
    it { should have_many(:price_histories).dependent(:destroy) }
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

  describe "#register_view!" do
    let(:owner) { create(:user) }
    let(:viewer) { create(:user) }
    let(:listing) { create(:listing, :active, user: owner) }

    context "when the viewer is the listing owner" do
      it "does not increment views_count" do
        expect { listing.register_view!(owner) }.not_to change { listing.reload.views_count }
      end

      it "returns false" do
        expect(listing.register_view!(owner)).to be false
      end
    end

    context "when the viewer is a signed-in non-owner on first view" do
      it "increments views_count by 1" do
        expect { listing.register_view!(viewer) }.to change { listing.reload.views_count }.by(1)
      end

      it "returns true" do
        expect(listing.register_view!(viewer)).to be true
      end
    end

    context "when the same signed-in non-owner views again (repeat view)" do
      before { listing.register_view!(viewer) }

      it "does not increment views_count a second time" do
        expect { listing.register_view!(viewer) }.not_to change { listing.reload.views_count }
      end

      it "returns false" do
        expect(listing.register_view!(viewer)).to be false
      end
    end

    context "when the viewer is a guest (nil)" do
      it "increments views_count by 1" do
        expect { listing.register_view!(nil) }.to change { listing.reload.views_count }.by(1)
      end

      it "returns true" do
        expect(listing.register_view!(nil)).to be true
      end

      it "increments again on a second guest request (no per-guest identity)" do
        listing.register_view!(nil)
        expect { listing.register_view!(nil) }.to change { listing.reload.views_count }.by(1)
      end
    end
  end

  describe "price history tracking" do
    let(:seller) { create(:user) }
    let(:listing) { create(:listing, :active, user: seller, price: 10_000, currency: "AFN") }

    it "creates a price history record when price changes" do
      expect { listing.update!(price: 8_000) }.to change { listing.price_histories.count }.by(1)
    end

    it "records old_price and new_price correctly" do
      listing.update!(price: 7_000)
      history = listing.price_histories.last
      expect(history.old_price).to eq(10_000)
      expect(history.new_price).to eq(7_000)
    end

    it "does not create a price history record when price is unchanged" do
      expect { listing.update!(title: "New title") }.not_to change { listing.price_histories.count }
    end

    describe "#price_dropped_at" do
      it "returns ISO-8601 timestamp of the most recent price reduction within 14 days" do
        listing.update!(price: 8_000)
        expect(listing.price_dropped_at).to be_a(String)
        expect(listing.price_dropped_at).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      it "returns nil when no price reduction exists" do
        expect(listing.price_dropped_at).to be_nil
      end

      it "returns nil when the reduction is older than 14 days" do
        create(:listing_price_history, :old_drop, listing: listing)
        expect(listing.price_dropped_at).to be_nil
      end

      it "returns nil when only price increases exist" do
        create(:listing_price_history, :increase, listing: listing, changed_at: 1.day.ago)
        expect(listing.price_dropped_at).to be_nil
      end
    end

    describe "#price_drop_percent" do
      it "returns the integer percent reduction" do
        listing.update!(price: 8_000) # 20% drop from 10_000
        expect(listing.price_drop_percent).to eq(20)
      end

      it "returns nil when no recent price reduction exists" do
        expect(listing.price_drop_percent).to be_nil
      end
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

    it "supports multi-word search (AND semantics)" do
      target = create(:listing, :active, title: "Samsung Galaxy Phone")
      create(:listing, :active, title: "Samsung Laptop")
      expect(Listing.search("samsung galaxy")).to contain_exactly(target)
    end

    it "returns all when blank" do
      create_list(:listing, 3, :active)
      expect(Listing.search("")).to match_array(Listing.all)
    end

    it "returns all when the query is only whitespace" do
      create_list(:listing, 2, :active)
      expect(Listing.search("   ")).to match_array(Listing.all)
    end

    describe "LIKE metacharacter escaping" do
      it "treats a literal '%' as a plain character, not a wildcard" do
        match   = create(:listing, :active, title: "50% off sale")
        nomatch = create(:listing, :active, title: "Big discount sale")
        results = Listing.search("50%")
        expect(results).to     include(match)
        expect(results).not_to include(nomatch)
      end

      it "does not match every listing when the query is just '%'" do
        listing_a = create(:listing, :active, title: "Normal item")
        listing_b = create(:listing, :active, title: "50% discount")
        results = Listing.search("%")
        expect(results).not_to include(listing_a)
        expect(results).to     include(listing_b)
      end

      it "treats a literal '_' as a plain character, not a single-char wildcard" do
        match   = create(:listing, :active, title: "model_x")
        nomatch = create(:listing, :active, title: "modelax")
        results = Listing.search("model_x")
        expect(results).to     include(match)
        expect(results).not_to include(nomatch)
      end

      it "does not match every listing when the query is just '_'" do
        listing_a = create(:listing, :active, title: "Normal item")
        listing_b = create(:listing, :active, title: "a_b model")
        results = Listing.search("_")
        expect(results).not_to include(listing_a)
        expect(results).to     include(listing_b)
      end
    end

    describe "MAX_SEARCH_WORDS cap" do
      it "defines a MAX_SEARCH_WORDS constant on the model" do
        expect(Listing::MAX_SEARCH_WORDS).to be_a(Integer)
        expect(Listing::MAX_SEARCH_WORDS).to be > 0
      end

      it "truncates an over-long query to at most MAX_SEARCH_WORDS words" do
        # Create a listing that matches the first MAX_SEARCH_WORDS words but
        # NOT a word that would appear only at position MAX_SEARCH_WORDS + 1.
        # We verify the result is non-empty (the cap prevented the extra AND
        # from filtering out the match).
        cap      = Listing::MAX_SEARCH_WORDS
        keywords = Array.new(cap) { |i| "word#{i}" }
        title    = keywords.join(" ")
        match    = create(:listing, :active, title: title)

        # Build a query with one extra word that does NOT appear in the title.
        # Without the cap the extra AND would eliminate `match`; with the cap
        # it is dropped so `match` should still be returned.
        extra_word = "xyznosuchtokenxyz"
        long_query = (keywords + [ extra_word ]).join(" ")

        expect(Listing.search(long_query)).to include(match)
      end

      it "includes the extra word when the query is at or below MAX_SEARCH_WORDS" do
        cap        = Listing::MAX_SEARCH_WORDS
        keywords   = Array.new(cap - 1) { |i| "word#{i}" }
        extra_word = "xyznosuchtokenxyz"
        title      = keywords.join(" ")
        match      = create(:listing, :active, title: title)

        # Within the cap so the extra word IS included in the search.
        within_cap_query = (keywords + [ extra_word ]).join(" ")
        # The extra word is not in the title, so match should NOT appear.
        expect(Listing.search(within_cap_query)).not_to include(match)
      end
    end
  end
end
