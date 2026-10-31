require "rails_helper"

# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md, 1.2.1): what the model owns —
# the keyword, the opt-in, the cap on followed searches, the pruning exemption,
# and THE definition of "this listing matches" (shared with the chip badge).
RSpec.describe SavedSearch, "alerts", type: :model do
  let(:user)   { create(:user) }
  let(:seller) { create(:user) }
  let(:phones) { create(:category, parent: create(:category)) }

  def live_listing(**attrs)
    create(:listing, :active, user: seller, category: phones, price: 15_000, title: "iPhone 12 Pro", **attrs)
  end

  describe "the keyword" do
    it "is part of the filter combination: same filters + another query is another search" do
      a = create(:saved_search, user: user, location: nil, category: phones, query: "iphone")
      b = create(:saved_search, user: user, location: nil, category: phones, query: "samsung")
      b.dedupe_siblings!

      expect(described_class.exists?(a.id)).to be true
    end
  end

  describe "the opt-in" do
    it "is off by default — the auto-saved history never alerts by itself" do
      expect(create(:saved_search, user: user).alert).to be false
    end

    it "allows at most MAX_ALERTS followed searches per user (code alerts_limit)" do
      create_list(:saved_search, described_class::MAX_ALERTS, user: user, alert: true)
      sixth = build(:saved_search, user: user, alert: true)

      expect(sixth).not_to be_valid
      expect(sixth.errors.details[:alert]).to include(a_hash_including(error: :alerts_limit))
    end

    it "is never pruned with the 4-chip history" do
      followed = create(:saved_search, user: user, alert: true, created_at: 10.days.ago)
      create_list(:saved_search, described_class::MAX_PER_USER, user: user)

      described_class.prune_for(user)
      expect(described_class.exists?(followed.id)).to be true
      expect(user.saved_searches.where(alert: false).count).to eq(described_class::MAX_PER_USER)
    end
  end

  describe "#matches?" do
    it "matches on category (its parent too), price and keyword, like Browse" do
      listing = live_listing
      parent_search = create(:saved_search, user: user, location: nil, category: phones.parent,
                                            price_max: 20_000, query: "iphone")

      expect(parent_search.matches?(listing)).to be true
      expect(create(:saved_search, user: user, location: nil, query: "samsung").matches?(listing)).to be false
      expect(create(:saved_search, user: user, location: nil, price_max: 10_000).matches?(listing)).to be false
    end

    it "never matches the searcher's own listing, nor one across a block" do
      own = create(:listing, :active, user: user, category: phones)
      search = create(:saved_search, user: user, location: nil)
      expect(search.matches?(own)).to be false

      create(:block, blocker: seller, blocked: user)
      expect(search.matches?(live_listing)).to be false
    end

    it "never matches a listing that is not browsable (sold, draft, removed)" do
      search = create(:saved_search, user: user, location: nil)

      expect(search.matches?(create(:listing, :sold, user: seller))).to be false
      expect(search.matches?(create(:listing, user: seller))).to be false # the factory's default is a draft
    end

    it "respects the radius" do
      search = create(:saved_search, user: user, location: nil, latitude: 34.5553, longitude: 69.2075, radius: 10)

      expect(search.matches?(live_listing(latitude: 34.56, longitude: 69.21))).to be true      # Kabul
      expect(search.matches?(live_listing(latitude: 31.6289, longitude: 65.7372))).to be false # Kandahar
    end
  end
end
