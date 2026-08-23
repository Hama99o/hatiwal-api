require "rails_helper"

RSpec.describe CategorySerializer, type: :serializer do
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

    # Both clients declare this field (mobile `Category.parentId`, web
    # `types.ts`) and it was never sent, so `parentId` was `undefined` on every
    # category and a `=== null` check for "top-level?" was false for all of them.
    it "exposes parent_id as nil for a top-level category" do
      expect(result).to have_key(:parent_id)
      expect(result[:parent_id]).to be_nil
    end

    it "exposes the parent's id for a subcategory" do
      sub = create(:category, parent: category)
      expect(described_class.render_as_hash(sub)[:parent_id]).to eq(category.id)
    end
  end

  describe ":with_counts view" do
    # The view is a pure reader: the controller precomputes every count in one
    # GROUP BY and hands them over as opts[:counts_by_id]. The roll-up itself is
    # covered in spec/requests/api/v1/categories_spec.rb.
    def render_with_counts(cat, counts = {})
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

    it "reads the count for its own id out of counts_by_id" do
      other = create(:category)
      result = render_with_counts(category, { category.id => 7, other.id => 99 })
      expect(result[:active_listings_count]).to eq(7)
    end

    context "when counts_by_id has no entry for the category" do
      it "returns 0 rather than nil" do
        result = render_with_counts(category)
        expect(result[:active_listings_count]).to eq(0)
      end
    end

    context "when counts_by_id is missing entirely" do
      it "still renders a 0 count" do
        result = described_class.render_as_hash(category, view: :with_counts)
        expect(result[:active_listings_count]).to eq(0)
      end
    end

    context "when category has subcategories" do
      let!(:active_sub)   { create(:category, parent: category, active: true, position: 1) }
      let!(:inactive_sub) { create(:category, parent: category, active: false, position: 2) }

      it "includes only active subcategories" do
        result = render_with_counts(category)
        expect(result[:subcategories].map { |s| s[:id] }).to eq([ active_sub.id ])
      end

      it "gives each subcategory its own active_listings_count" do
        result = render_with_counts(category, { category.id => 5, active_sub.id => 3 })
        expect(result[:subcategories].first[:active_listings_count]).to eq(3)
      end

      it "does not nest subcategories inside subcategories" do
        result = render_with_counts(category)
        expect(result[:subcategories].first).not_to have_key(:subcategories)
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
