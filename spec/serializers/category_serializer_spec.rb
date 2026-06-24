require "rails_helper"

RSpec.describe CategorySerializer, type: :serializer do
  let(:seller)   { create(:user) }
  let(:category) { create(:category, name_en: "Electronics", name_ps: "بریښنایي", name_fa: "الکترونیک", icon: "📱") }

  describe "default view" do
    subject(:result) { described_class.render_as_hash(category) }

    it "exposes id, slug, icon, position" do
      expect(result).to include(:id, :slug, :icon, :position)
    end

    it "exposes all three locale name fields" do
      expect(result[:name_en]).to eq("Electronics")
      expect(result[:name_ps]).to eq("بریښنایي")
      expect(result[:name_fa]).to eq("الکترونیک")
    end

    it "does not include active_listings_count in default view" do
      expect(result).not_to have_key(:active_listings_count)
    end
  end

  describe ":with_counts view" do
    # Helper: compute counts exactly as the controller does — a single
    # GROUP BY query so the serializer reads from opts[:counts_by_id].
    def render_with_counts(cat)
      counts = Listing.browsable
                      .except(:order)
                      .where(category_id: cat.id)
                      .group(:category_id)
                      .count
      described_class.render_as_hash(cat, view: :with_counts, counts_by_id: counts)
    end

    it "includes active_listings_count" do
      result = render_with_counts(category)
      expect(result).to have_key(:active_listings_count)
    end

    it "includes subcategories array" do
      result = render_with_counts(category)
      expect(result).to have_key(:subcategories)
      expect(result[:subcategories]).to be_an(Array)
    end

    context "when category has no listings" do
      it "returns 0 for active_listings_count" do
        result = render_with_counts(category)
        expect(result[:active_listings_count]).to eq(0)
      end
    end

    context "when category has only browsable (active, not expired, not removed) listings" do
      before do
        create(:listing, category: category, user: seller, status: :active)
      end

      it "counts the browsable listing" do
        result = render_with_counts(category)
        expect(result[:active_listings_count]).to eq(1)
      end
    end

    context "when category has a mix of browsable and non-browsable listings" do
      before do
        # browsable: active, not expired, not removed
        create(:listing, category: category, user: seller, status: :active)
        # draft — excluded
        create(:listing, category: category, user: seller, status: :draft)
        # sold — excluded
        create(:listing, category: category, user: seller, status: :sold)
        # expired — excluded
        create(:listing, category: category, user: seller, status: :active, expires_at: 1.hour.ago)
        # removed — excluded
        create(:listing, category: category, user: seller, status: :active, removed_at: 1.hour.ago)
      end

      it "counts only browsable listings" do
        result = render_with_counts(category)
        expect(result[:active_listings_count]).to eq(1)
      end
    end

    context "when category has subcategories" do
      before do
        create(:category, parent: category, active: true)
        create(:category, parent: category, active: false)
      end

      it "includes only active subcategories" do
        result = render_with_counts(category)
        expect(result[:subcategories].length).to eq(1)
      end
    end
  end

  describe ":with_subcategories view" do
    subject(:result) { described_class.render_as_hash(category, view: :with_subcategories) }

    it "includes subcategories array" do
      expect(result).to have_key(:subcategories)
      expect(result[:subcategories]).to be_an(Array)
    end

    it "does not include active_listings_count" do
      expect(result).not_to have_key(:active_listings_count)
    end
  end
end
