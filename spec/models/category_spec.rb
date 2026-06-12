require "rails_helper"

RSpec.describe Category, type: :model do
  describe "associations" do
    it { should have_many(:listings).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:category) }

    it { should validate_presence_of(:name_en) }
    it { should validate_presence_of(:name_ps) }
    it { should validate_presence_of(:name_fa) }
    it { should validate_presence_of(:slug) }
    it { should validate_uniqueness_of(:slug) }
  end

  describe "dependent: :restrict_with_error" do
    it "prevents destroying a category that has listings" do
      category = create(:category)
      create(:listing, category: category)

      expect(category.destroy).to be false
      expect(category.errors[:base]).to be_present
      expect(Category.exists?(category.id)).to be true
    end

    it "allows destroying a category with no listings" do
      category = create(:category)
      expect(category.destroy).to be_truthy
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns only active categories" do
        active   = create(:category, active: true)
        create(:category, active: false)
        expect(Category.active).to contain_exactly(active)
      end
    end

    describe ".ordered" do
      it "orders by position ascending" do
        third  = create(:category, position: 3)
        first  = create(:category, position: 1)
        second = create(:category, position: 2)
        expect(Category.ordered.to_a).to eq([ first, second, third ])
      end
    end
  end

  describe "#name_for" do
    let(:category) { build(:category, name_en: "Electronics", name_ps: "بریښنایي", name_fa: "الکترونیک") }

    it "returns Pashto name for ps" do
      expect(category.name_for("ps")).to eq("بریښنایي")
      expect(category.name_for(:ps)).to eq("بریښنایي")
    end

    it "returns Dari name for fa" do
      expect(category.name_for("fa")).to eq("الکترونیک")
    end

    it "returns English name for en" do
      expect(category.name_for("en")).to eq("Electronics")
    end

    it "falls back to English for unknown locale" do
      expect(category.name_for("xx")).to eq("Electronics")
      expect(category.name_for(nil)).to eq("Electronics")
    end
  end
end
