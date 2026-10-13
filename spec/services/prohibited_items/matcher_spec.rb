require "rails_helper"

# The matcher against the REAL starting list (config/prohibited_terms.yml), so
# a change to the list is checked against the owner's benign examples.
RSpec.describe ProhibitedItems::Matcher do
  before { ProhibitedTerm.seed_defaults! }

  let(:matcher) { described_class.current }

  def categories(text) = matcher.matches(text).map(&:category).uniq

  describe "benign titles never flag (owner, 2026-10-13)" do
    [
      "شیشه د کړکۍ", "د پخلنځي چاقو", "نسوار", "سګرټ", "پسه د خرڅلاو لپاره",
      "kitchen knife", "hunting boots", "glass bottle", "car battery",
      "Samsung phone, not stolen, with box", "موبایل دزدی نیست", "قفل ضد دزدی",
      "glue gun", "printer cartridge", "bullet camera CCTV", "wine red dress", "chaqoo چاقو تیز",
      "سیګار او تنباکو", "dagger with sheath", "چرګان د خرڅلاو", "spray gun for paint", "kidney beans 5kg"
    ].each do |title|
      it "lets “#{title}” through" do
        expect(matcher.matches(title)).to be_empty
      end
    end
  end

  describe "true positives, per category, in en / ps / fa" do
    {
      "firearms" => [ "Hunting rifle for sale", "AK-47 new", "تفنگ شکاری", "د ښکار ټوپک", "تمانچه روسی" ],
      "ammunition" => [ "9mm ammo box", "مرمی کلاشینکوف", "مرمۍ", "باروت اصل" ],
      "explosives" => [ "hand grenade", "نارنجک", "لاسي بم", "dynamite sticks" ],
      "drugs" => [ "pure heroin", "ترياك اصل", "چَرس", "هیروئین", "crystal meth", "مواد مخدر" ],
      "alcohol" => [ "Whiskey 12 years", "شراب", "ودکا روسی", "آبجو" ],
      "fake_documents" => [ "Fake Passport", "تذکره جعلی", "جعلي تذکره", "fake driving licence" ],
      "stolen_goods" => [ "stolen iPhone cheap", "گوشی سرقتی", "د غلا مال" ],
      "adult" => [ "porn dvd", "پورن", "فلم سوپر" ],
      "gambling" => [ "casino chips", "قمار", "شرط‌بندی فوتبال" ],
      "human_trafficking" => [ "kidney for sale", "فروش کلیه", "د انسان قاچاق" ],
      "medicine" => [ "Tramadol 100mg", "دوا د سر درد", "دارو", "درمل" ]
    }.each do |category, titles|
      titles.each do |title|
        it "flags “#{title}” as #{category}" do
          expect(categories(title)).to include(category)
        end
      end
    end
  end

  describe "matching rules" do
    subject(:custom) { described_class.new([ [ 1, "pistol", :firearms ], [ 2, "fake id", :fake_documents ], [ 3, "هیروئین*", :drugs ] ]) }

    it "matches whole words only" do
      expect(custom.matches("pistolet water toy")).to be_empty
      expect(custom.matches("old pistol")).to be_present
    end

    it "matches a Latin plural" do
      expect(custom.matches("two pistols").map(&:term)).to eq([ "pistol" ])
    end

    it "matches a phrase only when its words are next to each other" do
      expect(custom.matches("fake id card")).to be_present
      expect(custom.matches("id card, not fake")).to be_empty
    end

    it "matches the start of a word for a starred term" do
      expect(custom.matches("هیروئینو")).to be_present
    end

    it "looks across several texts but never across their border" do
      expect(custom.matches("title", "a pistol in the description")).to be_present
      expect(custom.matches("fake", "id")).to be_empty
    end

    it "ignores a negated mention but not a second, plain one" do
      expect(custom.matches("no pistol here")).to be_empty
      expect(custom.matches("no pistol here, but a pistol there")).to be_present
    end

    it "is empty for blank text" do
      expect(custom.matches(nil, "")).to be_empty
    end
  end

  describe ".current" do
    it "rebuilds when a term is added or removed" do
      expect(described_class.current.matches("zzqword")).to be_empty
      term = create(:prohibited_term, term: "zzqword")
      expect(described_class.current.matches("a zzqword")).to be_present
      term.destroy
      expect(described_class.current.matches("a zzqword")).to be_empty
    end
  end
end
