require "rails_helper"

RSpec.describe Listing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:category) }
    it { should have_many(:conversations).dependent(:nullify) }
    it { should have_many(:saved_listings).dependent(:destroy) }
    it { should have_many(:price_histories).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(150) }
    # `description` is a text column and was entirely unbounded — a client could
    # POST a megabyte of prose per listing.
    it { should validate_length_of(:description).is_at_most(described_class::MAX_DESCRIPTION_LENGTH) }

    it "still accepts a listing with no description at all" do
      expect(build(:listing, description: nil)).to be_valid
    end
    it { should validate_presence_of(:price) }
    it { should validate_numericality_of(:price).is_greater_than(0) }
    it { should validate_numericality_of(:price).is_less_than_or_equal_to(described_class::MAX_PRICE) }

    # Regression: `price` is decimal(12, 2). Before MAX_PRICE existed, a larger
    # value passed validation and then blew up in Postgres, reaching the mobile
    # app as a 500 with no field errors — the seller saw the publish fail with no
    # reason given. It must fail as an ordinary invalid record instead.
    it "rejects a price above the column ceiling rather than overflowing the column" do
      listing = build(:listing, price: described_class::MAX_PRICE + 1)

      expect(listing).not_to be_valid
      expect(listing.errors[:price]).to be_present
    end

    # The reported reproduction: a seller holds down "9" and submits a price of
    # several hundred digits. Rails casts it to a BigDecimal far beyond
    # decimal(12, 2), so without MAX_PRICE it reached Postgres and 500'd.
    it "rejects a price typed as hundreds of digits" do
      listing = build(:listing, price: "9" * 300)

      expect(listing).not_to be_valid
      expect(listing.errors[:price]).to be_present
    end

    it "does not raise when saving an absurdly large price" do
      listing = build(:listing, price: 10**12)

      expect { listing.save }.not_to raise_error
      expect(listing).not_to be_persisted
    end
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

      it "includes listings filed under the category's subcategories" do
        parent = create(:category)
        child  = create(:category, parent: parent)
        direct = create(:listing, category: parent)
        nested = create(:listing, category: child)
        create(:listing)

        expect(Listing.by_category(parent.id)).to contain_exactly(direct, nested)
      end

      it "does not widen a subcategory filter to its parent or siblings" do
        parent  = create(:category)
        child   = create(:category, parent: parent)
        sibling = create(:category, parent: parent)
        nested  = create(:listing, category: child)
        create(:listing, category: parent)
        create(:listing, category: sibling)

        expect(Listing.by_category(child.id)).to contain_exactly(nested)
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

    describe ".similar_to" do
      it "returns browsable same-category listings, newest first, without the source" do
        category = create(:category)
        source   = create(:listing, :active, category: category)
        older    = create(:listing, :active, category: category, created_at: 2.days.ago)
        newer    = create(:listing, :active, category: category, created_at: 1.hour.ago)
        create(:listing, :draft, category: category)
        create(:listing, :sold, category: category)
        create(:listing, :active)

        expect(Listing.similar_to(source).to_a).to eq([ newer, older ])
      end

      it "cross-sells the children's stock for a listing filed on a parent category" do
        parent = create(:category)
        child  = create(:category, parent: parent)
        source = create(:listing, :active, category: parent)
        nested = create(:listing, :active, category: child)

        expect(Listing.similar_to(source)).to contain_exactly(nested)
      end

      it "does not widen a child-category listing to its parent or siblings" do
        parent  = create(:category)
        child   = create(:category, parent: parent)
        sibling = create(:category, parent: parent)
        source  = create(:listing, :active, category: child)
        match   = create(:listing, :active, category: child)
        create(:listing, :active, category: parent)
        create(:listing, :active, category: sibling)

        expect(Listing.similar_to(source)).to contain_exactly(match)
      end

      it "caps the rail at 8" do
        category = create(:category)
        source   = create(:listing, :active, category: category)
        create_list(:listing, 9, :active, category: category)

        expect(Listing.similar_to(source).length).to eq(8)
      end
    end

    describe ".browsable" do
      it "returns active listings newest first" do
        create(:listing, :draft)
        old_active = create(:listing, :active, created_at: 2.days.ago)
        new_active = create(:listing, :active, created_at: 1.hour.ago)
        expect(Listing.browsable.to_a).to eq([ new_active, old_active ])
      end

      # SF-B1 — the load-bearing widen. Every browse surface (feed, search,
      # category counts, similar rail, recently-viewed, saved searches) composes
      # on this one scope, so a reserved listing being in it is what puts held
      # listings back on the market everywhere at once.
      it "includes reserved listings (SF-B1)" do
        reserved = create(:listing, :reserved)
        expect(Listing.browsable).to include(reserved)
      end

      it "still excludes draft, sold, expired and admin-removed listings" do
        draft    = create(:listing, :draft)
        sold     = create(:listing, :sold)
        expired  = create(:listing, :expired)
        removed  = create(:listing, :reserved, removed_at: Time.current)
        expect(Listing.browsable).not_to include(draft, sold, expired, removed)
      end

      it "excludes an EXPIRED reserved listing (the expiry clock now applies to holds)" do
        held_and_expired = create(:listing, :reserved, expires_at: 1.day.ago)
        expect(Listing.browsable).not_to include(held_and_expired)
      end
    end

    describe ".live" do
      it "returns active and reserved listings only" do
        active   = create(:listing, :active)
        reserved = create(:listing, :reserved)
        create(:listing, :draft)
        create(:listing, :sold)

        expect(Listing.live).to contain_exactly(active, reserved)
      end
    end

    describe ".for_status_filter" do
      # SF-B1 — the seller's "Active" tab is the `live` set, so a held listing
      # stays in the tab it was already in rather than needing a "Reserved" tab
      # the clients are dropping.
      it "'active' returns non-expired active AND reserved listings" do
        active   = create(:listing, :active)
        reserved = create(:listing, :reserved)
        create(:listing, :expired)
        create(:listing, :draft)

        expect(Listing.for_status_filter("active")).to contain_exactly(active, reserved)
      end

      it "'reserved' still returns exactly the reserved rows" do
        reserved = create(:listing, :reserved)
        create(:listing, :active)

        expect(Listing.for_status_filter("reserved")).to contain_exactly(reserved)
      end

      it "'expired' includes a reserved listing past its clock, so it can still be renewed" do
        expired_active   = create(:listing, :expired)
        expired_reserved = create(:listing, :reserved, expires_at: 1.day.ago)

        expect(Listing.for_status_filter("expired")).to contain_exactly(expired_active, expired_reserved)
      end

      # The two tabs must partition the live set — a listing that appears in
      # neither is invisible to its own seller, which is how a finished listing
      # gets stranded.
      it "partitions the live set between the 'active' and 'expired' buckets" do
        live_rows = [
          create(:listing, :active),
          create(:listing, :reserved),
          create(:listing, :expired),
          create(:listing, :reserved, expires_at: 1.day.ago)
        ]

        bucketed = Listing.for_status_filter("active").to_a + Listing.for_status_filter("expired").to_a
        expect(bucketed).to match_array(live_rows)
      end
    end

    describe ".with_recent_price_drop" do
      it "returns only listings with a price reduction recorded within the window, deduplicated" do
        discounted = create(:listing, :active, price: 1000)
        discounted.update!(price: 800)
        discounted.update!(price: 600) # a second drop — must not duplicate the row via the join

        increased = create(:listing, :active, price: 100)
        increased.update!(price: 200)

        unchanged = create(:listing, :active, price: 500)

        result = Listing.with_recent_price_drop
        expect(result).to contain_exactly(discounted)
        expect(result.to_a.count { |l| l.id == discounted.id }).to eq(1)
        expect(result).not_to include(increased, unchanged)
      end

      it "excludes drops older than the given window" do
        old_drop = create(:listing, :active, price: 1000)
        old_drop.update!(price: 500)
        ListingPriceHistory.last.update_column(:changed_at, 40.days.ago)

        expect(Listing.with_recent_price_drop(30)).not_to include(old_drop)
      end

      it "chains onto .browsable so non-browsable listings are excluded" do
        draft = create(:listing, price: 1000)
        draft.update!(price: 500)

        expect(Listing.browsable.with_recent_price_drop).not_to include(draft)
      end

      it "defaults to the same window as the price-drop badge (PRICE_DROP_WINDOW)" do
        borderline = create(:listing, :active, price: 1000)
        borderline.update!(price: 500)
        ListingPriceHistory.last.update_column(:changed_at, 20.days.ago) # inside old 30d window, outside 14d badge window

        expect(Listing.with_recent_price_drop).not_to include(borderline)
      end

      # Regression: the previous implementation used
      # `joins(:price_histories).distinct`, which forces
      # `SELECT DISTINCT listings.*` — incompatible with an ORDER BY on a
      # computed expression not in the SELECT list (e.g. `nearest_first`'s
      # Haversine `ORDER BY acos(...)`), raising
      # `PG::InvalidColumnReference` in Postgres. The `where(id: subquery)`
      # implementation keeps the SELECT list to plain `listings.*` so it
      # composes with any ORDER BY, including `nearest_first`.
      it "composes with .nearest_first without raising a Postgres error" do
        near = create(:listing, :active, price: 1000, latitude: 34.5800, longitude: 69.2100)
        near.update!(price: 800)
        far = create(:listing, :active, price: 1000, latitude: 34.3529, longitude: 62.2040)
        far.update!(price: 800)
        create(:listing, :active, price: 500, latitude: 34.5801, longitude: 69.2101) # unchanged, nearest of all

        result = nil
        expect {
          result = Listing.browsable.with_recent_price_drop.nearest_first(34.5553, 69.2075).to_a
        }.not_to raise_error

        expect(result.map(&:id)).to eq([ near.id, far.id ])
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

      it "sorts by views_count descending for most_viewed" do
        # Use view counts distinct from the other listings' default (0) so
        # the ordering is deterministic regardless of the cheap/expensive fixtures.
        popular  = create(:listing, :active, views_count: 100)
        moderate = create(:listing, :active, views_count: 50)
        # The cheap/expensive let!s have views_count: 0; popular and moderate
        # must appear before all zero-count listings.
        result = Listing.sorted("most_viewed").to_a
        expect(result.first).to eq(popular)
        expect(result.second).to eq(moderate)
      end
    end

    describe ".nearest_first" do
      # Kabul center — same reference point used by the request specs.
      let(:kabul_lat) { 34.5553 }
      let(:kabul_lng) { 69.2075 }

      it "orders listings closer-first by Haversine distance" do
        near = create(:listing, :active, latitude: 34.5800, longitude: 69.2100)  # ~3km
        far  = create(:listing, :active, latitude: 34.3529, longitude: 62.2040)  # ~570km

        result = Listing.nearest_first(kabul_lat, kabul_lng).to_a
        expect(result).to eq([ near, far ])
      end

      it "excludes listings without coordinates" do
        with_coords = create(:listing, :active, latitude: 34.5800, longitude: 69.2100)
        create(:listing, :active, latitude: nil, longitude: nil)

        expect(Listing.nearest_first(kabul_lat, kabul_lng)).to contain_exactly(with_coords)
      end

      it "composes with within_radius — radius filters, nearest_first orders" do
        near = create(:listing, :active, latitude: 34.5800, longitude: 69.2100)
        create(:listing, :active, latitude: 34.3529, longitude: 62.2040) # outside radius

        result = Listing.within_radius(kabul_lat, kabul_lng, 10).nearest_first(kabul_lat, kabul_lng).to_a
        expect(result).to eq([ near ])
      end

      it "falls back to the current scope (untouched) when lat/lng are blank" do
        create(:listing, :active, latitude: 34.5800, longitude: 69.2100)
        create(:listing, :active, latitude: nil, longitude: nil)

        result = Listing.nearest_first(nil, nil)
        expect(result.count).to eq(2)
      end
    end
  end

  # SF-B1 — the predicate form of the `live` scope, and the expiry widen that
  # rides with it.
  describe "#live? / #expired?" do
    it "is live for an active listing" do
      expect(create(:listing, :active)).to be_live
    end

    it "is live for a reserved listing — a hold is not a departure from the market" do
      expect(create(:listing, :reserved)).to be_live
    end

    it "is not live for a draft or a sold listing" do
      expect(create(:listing, :draft)).not_to be_live
      expect(create(:listing, :sold)).not_to be_live
    end

    it "expires a reserved listing past its clock (it used to sit live forever)" do
      expect(create(:listing, :reserved, expires_at: 1.day.ago)).to be_expired
    end

    it "does not expire a reserved listing whose clock has not run out" do
      expect(create(:listing, :reserved, expires_at: 1.day.from_now)).not_to be_expired
    end

    it "never reports a sold listing as expired" do
      expect(create(:listing, :sold, expires_at: 1.day.ago)).not_to be_expired
    end
  end

  describe "timestamp callbacks" do
    it "sets published_at when becoming active" do
      # :with_image because publishing now requires at least one photo.
      listing = create(:listing, :draft, :with_image)
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

    # SF-B10 kept this callback, narrowed to the one hold it is still the only
    # record of: a legacy bare `PUT .../reserve` with no buyer_id writes no
    # Transaction, so `status: reserved` is all there is to date. Every hold
    # placed through the buyer picker is dated by #reconcile_hold_stamp! instead.
    it "sets reserved_at when becoming reserved with no ledger row to date it" do
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

  # ── TASK-TX01 — buyer-recorded reserve/sold ─────────────────────────────────
  describe "#reserve_with_buyer! / #sold_with_buyer!" do
    let(:seller)   { create(:user) }
    let(:listing)  { create(:listing, :active, user: seller) }
    let(:buyer)    { create(:user) }

    before { create(:conversation, listing: listing, seller: seller, buyer: buyer) }

    it "reserve_with_buyer! is a no-op and returns nil when buyer_id is blank (legacy path)" do
      expect(listing.reserve_with_buyer!(buyer_id: nil)).to be_nil
      expect(listing.sale_transactions).to be_empty
    end

    # SF-B3 — no longer a no-op. `reserve_with_buyer!` above still is (a hold on
    # nobody is not a hold), but a SALE with nobody named is still a sale, and
    # recording nothing is what made it unviewable and uncorrectable.
    it "sold_with_buyer! records a buyer-less sale when buyer_id is blank (SF-B3)" do
      txn = listing.sold_with_buyer!(buyer_id: nil)

      expect(txn).to be_present
      expect(txn).to be_sold
      expect(txn.buyer_id).to be_nil
      expect(txn.seller_id).to eq(listing.user_id)
      expect(listing.sale_transactions.reload).to contain_exactly(txn)
    end

    # ── TASK-TX02 (review fix) — a listing genuinely CURRENTLY reserved with
    # a confirmed buyer (its own status flipped to `reserved`, mirroring what
    # the `reserve` controller action always does right after
    # reserve_with_buyer!) must still close out to `sold` using its own
    # recorded buyer when the sold call comes in buyer-less with no explicit
    # `clear_buyer` — the true LEGACY-client case (never sends any buyer
    # info at all). ──────────────────────────────────────────────────────────
    it "sold_with_buyer! closes out a still-reserved Transaction using its own buyer when buyer_id is blank (legacy)" do
      reserved = listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!

      txn = listing.sold_with_buyer!(buyer_id: nil)

      expect(txn.id).to eq(reserved.id)
      expect(txn).to be_sold
      expect(txn.buyer_id).to eq(buyer.id)
      expect(txn.completed_at).to be_present
    end

    # ── TASK-TX02 (review fix, MAJOR — "clear_buyer must not re-attribute") ──
    it "sold_with_buyer! with clear_buyer: true cancels a still-reserved Transaction instead of closing it out" do
      reserved = listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!

      txn = listing.sold_with_buyer!(buyer_id: nil, clear_buyer: true)

      # The reserved row is still destroyed (never re-attributed) — but SF-B3
      # writes the sale itself down instead of returning nil, so the seller can
      # see it afterwards and SF-B4 can correct it.
      expect(Transaction.exists?(reserved.id)).to be(false)
      expect(txn).to be_present
      expect(txn).to be_sold
      expect(txn.buyer_id).to be_nil
      expect(listing.sale_transactions.reload).to contain_exactly(txn)
    end

    # ── TASK-TX02 (review fix, MAJOR — gate the close-out on `reserved?`) ────
    # Reproduces the reviewer's exact repro: a reservation that has already
    # fallen through (the listing's own status is no longer `reserved`) must
    # never be closed out by a later buyer-less sold call, even if a stale
    # Transaction row somehow still exists — the listing's CURRENT status is
    # the source of truth, not the mere presence of an old row.
    it "sold_with_buyer! ignores a stale reserved Transaction once the listing is no longer reserved" do
      stale = listing.reserve_with_buyer!(buyer_id: buyer.id)
      # Deliberately do NOT call `listing.reserved!` / `cancel_open_transaction!`
      # here — this isolates the buyer-less half of the gate. The real `activate`
      # controller action calls `cancel_open_transaction!` explicitly (covered
      # by its own spec below), so in production this stale row never survives.
      #
      # SF-B9 narrowed what "stale" can mean without weakening this: the
      # close-out now keys on the BUYER, and this call names none, so the row is
      # still left alone. A call that DID name this hold's buyer would close it
      # out — correctly, because since SF-B2 a hold on an `active` listing is the
      # normal shape for a batch, not evidence of staleness.
      expect(listing).not_to be_reserved

      txn = listing.sold_with_buyer!(buyer_id: nil)

      expect(stale.reload).to be_reserved # untouched — not silently closed out
      # SF-B3: the sale is recorded as its own buyer-less row rather than
      # vanishing. The point of this spec is unchanged — the stale hold is not
      # what got sold.
      expect(txn).to be_present
      expect(txn.id).not_to eq(stale.id)
      expect(txn.buyer_id).to be_nil
    end

    # ── SF-B9 — the close-out gate is the BUYER, not the listing's status ─────
    #
    # `existing = reserved? ? open_transaction : nil` read the listing's status
    # as a proxy for "a hold is in progress". SF-B2 broke that proxy: a
    # multi-unit batch deliberately stays `active` while units are held, so for
    # every batch the gate was permanently closed and a sale to the very buyer
    # holding the units left the hold open next to it. The end-to-end
    # consequences (a buyer shown "5 available · 10 held" for units already sold
    # to them, and SF-B8 refusing legitimate down-edits) are covered in
    # spec/requests/api/v1/my/listing_hold_close_out_spec.rb — `sold_units` moves
    # in the CONTROLLER, so only the request layer can assert those numbers.
    it "sold_with_buyer! closes out a batch's open hold when the sale names the same buyer (SF-B9)" do
      batch = create(:listing, :active, user: seller, quantity: 15)
      create(:conversation, listing: batch, seller: seller, buyer: buyer)
      hold = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 10)
      expect(batch.reload).to be_active # NOT `reserved` — that is the whole point

      txn = batch.sold_with_buyer!(buyer_id: buyer.id, quantity: 10)

      expect(txn.id).to eq(hold.id)
      expect(txn).to be_sold
      expect(txn.quantity).to eq(10)
      expect(batch.sale_transactions.reload.count).to eq(1)
      expect(batch.open_transaction).to be_nil
      expect(batch.held_units).to eq(0)
    end

    it "sold_with_buyer! leaves a hold belonging to a DIFFERENT buyer alone (SF-B9 keeps TASK-TX02)" do
      other = create(:user)
      batch = create(:listing, :active, user: seller, quantity: 15)
      [ buyer, other ].each { |b| create(:conversation, listing: batch, seller: seller, buyer: b) }
      hold = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 10)

      txn = batch.sold_with_buyer!(buyer_id: other.id, quantity: 2)

      expect(txn.id).not_to eq(hold.id)
      expect(txn.buyer_id).to eq(other.id)
      # The other buyer's hold is never repurposed into this sale.
      expect(hold.reload).to be_reserved
      expect(hold.buyer_id).to eq(buyer.id)
      expect(hold.quantity).to eq(10)
    end

    # ── SF-B9 — the advisory hold is kept inside the remaining stock ──────────
    describe "#record_units_sold! and a surviving hold" do
      let(:batch) { create(:listing, :active, user: seller, quantity: 15) }

      before { create(:conversation, listing: batch, seller: seller, buyer: buyer) }

      it "leaves a hold that still fits untouched" do
        batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 10)

        batch.record_units_sold!(3)

        expect(batch.reload.available_units).to eq(12)
        expect(batch.held_units).to eq(10)
      end

      it "narrows a hold the sale no longer leaves room for" do
        hold = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 10)

        batch.record_units_sold!(12)

        expect(batch.reload.available_units).to eq(3)
        expect(hold.reload.quantity).to eq(3)
        expect(batch.held_units).to eq(3)
      end

      it "destroys a hold once nothing is left to hold" do
        hold = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 10)

        batch.record_units_sold!(15)

        expect(Transaction.exists?(hold.id)).to be(false)
        expect(batch.reload.held_units).to eq(0)
        expect(batch.available_units).to eq(0)
      end

      it "never widens a hold when stock is added back" do
        hold = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 2)

        batch.record_units_sold!(1)

        expect(hold.reload.quantity).to eq(2)
      end
    end

    # ── TASK-TX02 (review fix, MAJOR — activate cancels the open reservation) ─
    describe "#cancel_open_transaction!" do
      it "destroys a still-open reserved Transaction" do
        txn = listing.reserve_with_buyer!(buyer_id: buyer.id)

        listing.cancel_open_transaction!

        expect(Transaction.exists?(txn.id)).to be(false)
        expect(listing.sale_transactions.reload).to be_empty
      end

      it "is a no-op when there is no open Transaction" do
        expect { listing.cancel_open_transaction! }.not_to raise_error
      end
    end

    # ── SF-B10 — reserved_at is derived from the hold, in one place ───────────
    describe "#reconcile_hold_stamp!" do
      it "dates the listing from the open hold's created_at, never from now" do
        txn = listing.reserve_with_buyer!(buyer_id: buyer.id)
        # Simulate a hold placed days ago (the pre-fix rows the backfill repairs).
        txn.update_columns(created_at: 3.days.ago)
        listing.update_columns(reserved_at: nil)

        listing.reconcile_hold_stamp!

        expect(listing.reload.reserved_at.to_i).to eq(txn.reload.created_at.to_i)
      end

      it "clears the stamp when no hold is open" do
        listing.reserve_with_buyer!(buyer_id: buyer.id)
        listing.reconcile_hold_stamp!
        expect(listing.reload.reserved_at).to be_present

        listing.sale_transactions.destroy_all
        listing.reconcile_hold_stamp!

        expect(listing.reload.reserved_at).to be_nil
      end

      it "never reads a SOLD row as a hold" do
        listing.reserve_with_buyer!(buyer_id: buyer.id)
        listing.open_transaction.mark_sold!

        listing.reconcile_hold_stamp!

        expect(listing.reload.reserved_at).to be_nil
      end

      it "issues no write when the stamp is already correct (idempotent)" do
        listing.reserve_with_buyer!(buyer_id: buyer.id)

        writes = 0
        ActiveSupport::Notifications.subscribed(
          ->(*, payload) { writes += 1 if payload[:sql].to_s.start_with?("UPDATE \"listings\"") },
          "sql.active_record"
        ) { 3.times { listing.reconcile_hold_stamp! } }

        expect(writes).to eq(0)
      end
    end

    it "reserve_with_buyer! creates a reserved Transaction defaulting final_price to the listing price" do
      txn = listing.reserve_with_buyer!(buyer_id: buyer.id)

      expect(txn).to be_reserved
      expect(txn.buyer_id).to eq(buyer.id)
      expect(txn.seller_id).to eq(seller.id)
      expect(txn.final_price.to_f).to eq(listing.price.to_f)
      expect(listing.open_transaction).to eq(txn)
    end

    it "reserve_with_buyer! honors an explicit final_price" do
      txn = listing.reserve_with_buyer!(buyer_id: buyer.id, final_price: 5000)
      expect(txn.final_price.to_i).to eq(5000)
    end

    it "sold_with_buyer! advances an existing reserved Transaction to sold" do
      reserved = listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!

      txn = listing.sold_with_buyer!(buyer_id: buyer.id)

      expect(txn.id).to eq(reserved.id)
      expect(txn).to be_sold
      expect(txn.completed_at).to be_present
    end

    it "sold_with_buyer! creates a sold Transaction directly when selling straight from active" do
      txn = listing.sold_with_buyer!(buyer_id: buyer.id)

      expect(txn).to be_sold
      expect(txn.completed_at).to be_present
      expect(listing.sale_transactions.count).to eq(1)
    end

    it "re-reserving with a different (also-participant) buyer updates the existing open transaction instead of violating the unique index" do
      other_buyer = create(:user)
      create(:conversation, listing: listing, seller: seller, buyer: other_buyer)

      first  = listing.reserve_with_buyer!(buyer_id: buyer.id)
      second = listing.reserve_with_buyer!(buyer_id: other_buyer.id)

      expect(second.id).to eq(first.id)
      expect(second.reload.buyer_id).to eq(other_buyer.id)
    end
  end

  # ── TASK-R418 — the owner-only "who is the current buyer" lookup ───────────
  # CR fix (CYCLE-4, HIGH): previously ZERO spec coverage, and the
  # implementation picked the most-recently-CREATED Transaction row rather
  # than the one whose own status actually matches the listing's current
  # status — see the fix comment on Listing#current_sale itself.
  describe "#current_sale" do
    let(:seller)      { create(:user) }
    let(:buyer)       { create(:user) }
    let(:other_buyer) { create(:user) }
    let(:listing)     { create(:listing, :active, user: seller) }

    before do
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      create(:conversation, listing: listing, seller: seller, buyer: other_buyer)
    end

    it "returns nil for a draft/active listing that has never been reserved or sold" do
      expect(listing.current_sale).to be_nil
    end

    it "returns nil when reserved without ever identifying a buyer (legacy path)" do
      listing.reserved!
      expect(listing.current_sale).to be_nil
    end

    it "returns nil when sold without ever identifying a buyer (legacy path)" do
      listing.sold!
      expect(listing.current_sale).to be_nil
    end

    it "returns the reserved Transaction with its buyer while the listing is reserved" do
      txn = listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!

      expect(listing.current_sale).to eq(txn)
      expect(listing.current_sale.buyer_id).to eq(buyer.id)
      expect(listing.current_sale).to be_reserved
    end

    it "returns the sold Transaction with its buyer once the listing is sold" do
      listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!
      txn = listing.sold_with_buyer!(buyer_id: buyer.id)
      listing.sold!

      expect(listing.current_sale).to eq(txn)
      expect(listing.current_sale).to be_sold
    end

    # The exact repro the review flagged: a listing can end up with a
    # Transaction row whose OWN status no longer matches where the listing
    # itself is right now — e.g. an admin flips `status` directly via
    # Administrate, bypassing reserve_with_buyer!/sold_with_buyer! entirely
    # (see Transaction#bump_trust_counters!'s own documented admin-bypass
    # note). A newer but status-MISMATCHED row must never be surfaced as the
    # current sale — better to show nothing than the wrong buyer.
    it "ignores a newer Transaction row whose status does not match the listing's current status (unloaded)" do
      sold_txn = create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)
      stale_reserved = create(:transaction, listing: listing, seller: seller, buyer: other_buyer)
      stale_reserved.update_column(:created_at, sold_txn.created_at + 1.hour)

      listing.sold!
      listing.reload

      expect(listing.sale_transactions.loaded?).to be(false)
      expect(listing.current_sale).to eq(sold_txn)
      expect(listing.current_sale.buyer_id).to eq(buyer.id)
    end

    it "applies the same status filter when sale_transactions is already eager-loaded" do
      sold_txn = create(:transaction, :sold, listing: listing, seller: seller, buyer: buyer)
      stale_reserved = create(:transaction, listing: listing, seller: seller, buyer: other_buyer)
      stale_reserved.update_column(:created_at, sold_txn.created_at + 1.hour)

      listing.sold!
      # Eager-load exactly like My::ListingsController#index does — exercises
      # the `sale_transactions.loaded?` branch (filter-in-Ruby) instead of the
      # `.where(...)` fallback covered above. The dedicated N+1 query-count
      # assertion for this exact shape already lives at the request-spec
      # layer (spec/requests/api/v1/my/listings_spec.rb, "sale (owner-only
      # buyer identity) on the seller feed") — this spec only re-asserts
      # correctness of the loaded branch.
      reloaded = Listing.includes(:sale_transactions).find(listing.id)
      expect(reloaded.sale_transactions.loaded?).to be(true)

      expect(reloaded.current_sale).to eq(sold_txn)
      expect(reloaded.current_sale.buyer_id).to eq(buyer.id)
    end

    # SF-B2 — the case the old `reserved? || sold?` gate was blind to. A
    # multi-unit listing deliberately keeps status `active` while units are held
    # (My::ListingsController#reserve), so `current_sale` returned nil and the
    # seller's own card showed no buyer for a hold they had just placed.
    it "surfaces an open hold on an ACTIVE multi-unit listing (SF-B2)" do
      batch = create(:listing, :active, user: seller, quantity: 15)
      create(:conversation, listing: batch, seller: seller, buyer: buyer)

      txn = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 3)

      expect(batch.reload).to be_active
      expect(batch.current_sale).to eq(txn)
      expect(batch.current_sale.quantity).to eq(3)
    end

    it "surfaces the open hold from an eager-loaded association without a fresh query" do
      batch = create(:listing, :active, user: seller, quantity: 15)
      create(:conversation, listing: batch, seller: seller, buyer: buyer)
      txn = batch.reserve_with_buyer!(buyer_id: buyer.id, quantity: 3)

      reloaded = Listing.includes(:sale_transactions).find(batch.id)
      expect(reloaded.sale_transactions.loaded?).to be(true)
      expect(reloaded.current_sale).to eq(txn)
    end
  end

  # SF-B2 — the public-safe half of "N held". A COUNT, never an identity: this
  # field ships on the base serializer view, guests included.
  describe "#held_units" do
    let(:seller)  { create(:user) }
    let(:buyer)   { create(:user) }
    let(:listing) { create(:listing, :active, user: seller, quantity: 15) }

    before { create(:conversation, listing: listing, seller: seller, buyer: buyer) }

    it "is 0 when nothing is held" do
      expect(listing.held_units).to eq(0)
    end

    it "reports the held quantity of the open hold" do
      listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 4)
      expect(listing.reload.held_units).to eq(4)
    end

    it "is 1 for a held single-item listing" do
      single = create(:listing, :active, user: seller, quantity: 1)
      create(:conversation, listing: single, seller: seller, buyer: buyer)
      single.reserve_with_buyer!(buyer_id: buyer.id)

      expect(single.reload.held_units).to eq(1)
    end

    it "returns to 0 once the hold is cancelled" do
      listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 4)
      listing.cancel_open_transaction!

      expect(listing.reload.held_units).to eq(0)
    end

    it "ignores a SOLD transaction — sold units are not held units" do
      listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 4)

      expect(listing.reload.held_units).to eq(0)
    end

    it "does not subtract from available_units — a hold is advisory, not inventory" do
      listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 4)

      expect(listing.reload.available_units).to eq(15)
    end
  end

  # SF-B2 — the optional hold quantity. Without it every reservation was
  # `quantity: 1`, so "N held for Ahmad" could only ever read "1 held".
  describe "#reserve_with_buyer! quantity" do
    let(:seller) { create(:user) }
    let(:buyer)  { create(:user) }

    def held(quantity:, requested:)
      listing = create(:listing, :active, user: seller, quantity: quantity)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: requested)
    end

    it "stores the requested units on a batch" do
      expect(held(quantity: 15, requested: 3).quantity).to eq(3)
    end

    it "defaults a batch to ONE unit — holding the whole shelf is a deliberate act" do
      expect(held(quantity: 15, requested: nil).quantity).to eq(1)
    end

    it "clamps above the available stock" do
      expect(held(quantity: 3, requested: 99).quantity).to eq(3)
    end

    it "clamps a zero or negative request up to 1" do
      expect(held(quantity: 15, requested: 0).quantity).to eq(1)
      expect(held(quantity: 15, requested: -5).quantity).to eq(1)
    end

    it "ignores the quantity entirely on a single-item listing" do
      expect(held(quantity: 1, requested: 9).quantity).to eq(1)
    end

    it "clamps to 1 on a sold-out batch rather than violating the DB check constraint" do
      listing = create(:listing, :active, user: seller, quantity: 2, sold_units: 2)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)

      expect(listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 5).quantity).to eq(1)
    end
  end

  # ── SF-B3 — `bump_seller_sold_count_for_legacy_sale!` is GONE. It existed only
  # because an outside-buyer sale created no Transaction and so nothing counted
  # it; that sale now always creates one and
  # Transaction#bump_trust_counters! counts it like any other. The specs that
  # used to live here asserted the manual bump; what matters now is that the
  # counter moves EXACTLY ONCE per outside-buyer sale — the double-count trap —
  # which is asserted end to end in
  # spec/requests/api/v1/my/listing_outside_buyer_spec.rb. ──────────────────
  describe "sold_count on a listing flipped to sold directly" do
    let(:seller) { create(:user) }

    it "is never bumped by an implicit callback — only a Transaction counts a sale" do
      listing = create(:listing, :active, user: seller)

      expect { listing.sold! }.not_to change { seller.reload.sold_count }
    end
  end

  # ── SF-B8 — the open-hold floor under `quantity` ────────────────────────────
  #
  # SF-B6 validated `quantity >= sold_units`; nothing validated it against an
  # OPEN HOLD, so a 15-unit listing with 10 held accepted `quantity: 2` and the
  # buyer-facing pill rendered "2 available · 10 held". The edit is REFUSED, never
  # resolved by silently shrinking someone's reservation.
  describe "quantity vs. an open hold (SF-B8)" do
    let(:seller) { create(:user) }
    let(:buyer)  { create(:user) }

    def held_listing(total:, held:, sold: 0)
      listing = create(:listing, :active, user: seller, quantity: total, sold_units: sold)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: held)
      listing.reload
    end

    it "refuses a quantity below the held units, with the error on :quantity" do
      listing = held_listing(total: 15, held: 10)

      listing.quantity = 2

      expect(listing).not_to be_valid
      expect(listing.errors.where(:quantity, Listing::QUANTITY_BELOW_HELD_UNITS)).to be_present
      expect(listing.errors.full_messages).to eq([
        "Quantity cannot be less than the 10 units on hold for a buyer. " \
        "Release the hold first, or set it to 10 or more."
      ])
    end

    it "maps to the machine-readable wire code the 3-locale clients localize off" do
      listing = held_listing(total: 15, held: 10)
      listing.quantity = 2
      listing.validate

      expect(listing.error_code).to eq("quantity_below_held_units")
      expect(listing.error_code).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)
    end

    it "allows exactly the held count, and anything above it" do
      listing = held_listing(total: 15, held: 10)

      expect(listing.tap { |l| l.quantity = 10 }).to be_valid
      expect(listing.tap { |l| l.quantity = 11 }).to be_valid
      expect(listing.tap { |l| l.quantity = 40 }).to be_valid
    end

    it "leaves a listing with no open hold alone" do
      listing = create(:listing, :active, user: seller, quantity: 15)

      listing.quantity = 1

      expect(listing).to be_valid
    end

    it "ignores a hold that has been released" do
      listing = held_listing(total: 15, held: 10)
      listing.cancel_open_transaction!

      expect(listing.reload.tap { |l| l.quantity = 2 }).to be_valid
    end

    it "ignores a SOLD transaction — those are sold units, not held ones" do
      listing = create(:listing, :active, user: seller, quantity: 15)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 4)
      listing.record_units_sold!(4)

      # Refused by the SF-B6 floor (4 sold), not by this one.
      listing.quantity = 2
      expect(listing).not_to be_valid
      expect(listing.error_code).to eq(Listing::QUANTITY_BELOW_SOLD_UNITS_CODE)
    end

    it "never fires on a single-item listing — its floor is already 1" do
      listing = create(:listing, :active, user: seller, quantity: 1)
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!

      expect(listing.reload.held_units).to eq(1)
      expect(listing.tap { |l| l.quantity = 1 }).to be_valid
    end

    it "is not consulted when `quantity` is not changing — an existing bad row stays editable" do
      listing = held_listing(total: 15, held: 10)
      listing.update_column(:quantity, 2) # the row this bug has been producing

      listing.reload.title = "Same bags, new photo"

      expect(listing).to be_valid
      expect(listing.renew!).to be(true)
    end

    it "is not consulted on create — a brand-new listing cannot hold anything" do
      listing = build(:listing, user: seller, quantity: 1)

      expect(listing).to be_valid
    end

    describe "when the sold-units floor applies too" do
      it "reports ONLY the held floor when the hold is higher" do
        listing = held_listing(total: 20, held: 10, sold: 8)

        listing.quantity = 5
        listing.validate

        expect(listing.errors[:quantity].size).to eq(1)
        expect(listing.errors[:quantity].first).to include("10 units on hold")
        expect(listing.error_code).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)
      end

      it "reports ONLY the sold floor when that is higher" do
        listing = held_listing(total: 20, held: 5, sold: 12)

        listing.quantity = 6
        listing.validate

        expect(listing.errors[:quantity].size).to eq(1)
        expect(listing.errors[:quantity].first).to include("12 units already sold")
        expect(listing.error_code).to eq(Listing::QUANTITY_BELOW_SOLD_UNITS_CODE)
      end

      it "names a minimum that actually works — the two floors never contradict" do
        listing = held_listing(total: 20, held: 10, sold: 8)

        # The lower floor alone (8 sold) is NOT offered as a fix, because 8 is
        # still refused by the hold.
        listing.quantity = 8
        expect(listing).not_to be_valid
        expect(listing.error_code).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)

        listing.quantity = 10
        expect(listing).to be_valid
      end
    end
  end
end
