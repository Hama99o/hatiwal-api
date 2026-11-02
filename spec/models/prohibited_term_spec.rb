require "rails_helper"

RSpec.describe ProhibitedTerm, type: :model do
  describe "validations" do
    subject { build(:prohibited_term) }

    it { is_expected.to validate_presence_of(:term) }
    it { is_expected.to define_enum_for(:locale).with_values(en: 0, ps: 1, fa: 2, any: 3).with_prefix(:locale) }
    it { is_expected.to define_enum_for(:category).with_values(described_class::CATEGORIES).with_prefix(:category) }

    it "refuses the same term twice for one language, after normalizing" do
      create(:prohibited_term, term: "تریاک", locale: :fa)
      expect(build(:prohibited_term, term: "ترياك", locale: :fa)).not_to be_valid
      expect(build(:prohibited_term, term: "ترياك", locale: :ps)).to be_valid
    end
  end

  it "stores the term normalized" do
    expect(create(:prohibited_term, term: "  Fake  ID ").term).to eq("fake id")
    expect(create(:prohibited_term, term: "هيروئين*").term).to eq("هیروئین*")
  end

  describe ".seed_defaults!" do
    it "adds the starting list once and is safe to run again" do
      added = described_class.seed_defaults!
      expect(added).to be > 150
      expect(described_class.seed_defaults!).to eq(0)
      expect(described_class.count).to eq(added)
    end

    it "covers every forbidden category plus medicine" do
      described_class.seed_defaults!
      expect(described_class.distinct.pluck(:category)).to match_array(described_class::CATEGORIES.keys.map(&:to_s) - [ "other" ])
    end

    it "never overwrites what an admin changed" do
      described_class.seed_defaults!
      described_class.find_by!(term: "opium").update!(note: "kept", category: :medicine)

      described_class.seed_defaults!

      expect(described_class.find_by!(term: "opium")).to have_attributes(note: "kept", category: "medicine")
    end

    it "only adds what is missing (a term deleted since comes back on a manual re-run)" do
      described_class.seed_defaults!
      described_class.find_by!(term: "heroin").destroy
      expect(described_class.seed_defaults!).to eq(1)
    end

    it "leaves out the words the owner allowed or that mislead" do
      described_class.seed_defaults!
      expect(described_class.where(term: %w[شیشه چاقو نسوار سګرټ gun knife]).count).to eq(0)
    end
  end
end
