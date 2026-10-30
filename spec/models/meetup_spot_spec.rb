require "rails_helper"

# IDEA-6 (docs/SAFE_MEETUP_SPOTS.md): busy public places suggested when two
# people arrange a meetup. Admin-edited; the draft list arrives switched off and
# marked "needs local check" until someone local approves each row.
RSpec.describe MeetupSpot, type: :model do
  it "needs a city, an English name, a kind and a real point" do
    spot = build(:meetup_spot, city_key: nil, name_en: "", latitude: 91, longitude: nil)
    expect(spot).not_to be_valid
    expect(spot.errors.attribute_names).to include(:city_key, :name_en, :latitude, :longitude)
  end

  it "has only the approved kinds: malls and bazaars (no police, no shrines, no banks)" do
    expect(described_class.kinds.keys).to eq(%w[mall bazaar])
  end

  it "shown = active rows only, by city then position" do
    b = create(:meetup_spot, city_key: "herat", position: 2)
    a = create(:meetup_spot, city_key: "herat", position: 1)
    create(:meetup_spot, active: false)
    expect(described_class.shown).to eq([ a, b ])
  end

  it "name_for: the user's language, then Dari, then English" do
    spot = build(:meetup_spot, name_en: "Majid Mall", name_fa: "مجید مال", name_ps: nil, name_ur: nil)
    expect(spot.name_for("fa")).to eq("مجید مال")
    expect(spot.name_for("ps")).to eq("مجید مال")
    expect(spot.name_for("ur")).to eq("Majid Mall")
    expect(spot.name_for("en")).to eq("Majid Mall")
  end

  describe ".seed_defaults!" do
    it "adds the draft list switched OFF and marked needs_local_check; never edits a row; safe to run again" do
      added = described_class.seed_defaults!
      expect(added).to be >= 15
      expect(described_class.where(active: true)).to be_empty
      expect(described_class.where(needs_local_check: false)).to be_empty
      expect(described_class.distinct.pluck(:city_key)).to match_array(%w[kabul herat kandahar mazar jalalabad])

      edited = described_class.find_by!(name_en: "Kabul City Centre")
      edited.update!(active: true, needs_local_check: false, name_ps: "کابل ښار مرکز")
      expect(described_class.seed_defaults!).to eq(0)
      expect(edited.reload).to have_attributes(active: true, needs_local_check: false, name_ps: "کابل ښار مرکز")
    end
  end
end
