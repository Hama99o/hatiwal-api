require "rails_helper"

# LOC-1 — own address → guessed → Kabul (hatiwal-mobile/docs/USER_LOCATION.md).
RSpec.describe User, "location" do
  let(:herat) { { latitude: 34.3529, longitude: 62.2040 } }
  let(:user) { create(:user, city: nil, province: nil, latitude: nil, longitude: nil) }

  describe "#effective_location" do
    it "is Kabul with source default when nothing is known" do
      expect(user.effective_location).to eq(latitude: 34.5553, longitude: 69.2075, province: "Kabul", source: "default")
    end

    it "uses the guess when there is no own address" do
      user.record_location_guess!(**herat, source: User::GuessSource::LISTING)
      expect(user.effective_location).to include(source: "guess", province: "Herat", latitude: 34.3529)
    end

    it "uses the own map point over a guess" do
      user.record_location_guess!(**herat, source: User::GuessSource::GPS)
      user.update!(latitude: 34.5553, longitude: 69.2075, province: "Kabul")
      expect(user.effective_location).to include(source: "own", province: "Kabul", latitude: 34.5553)
    end

    it "uses the capital of the own province when there is no map point" do
      user.update!(province: "Balkh")
      expect(user.effective_location).to eq(latitude: 36.709, longitude: 67.1109, province: "Balkh", source: "own")
    end

    it "treats an own address abroad as no address (falls back to the guess, then Kabul)" do
      user.update!(latitude: 25.2, longitude: 55.27) # Dubai
      expect(user.effective_location[:source]).to eq("default")
      user.record_location_guess!(**herat, source: User::GuessSource::LISTING)
      expect(user.effective_location[:source]).to eq("guess")
    end
  end

  describe "#record_location_guess!" do
    it "stores the clue with its source and time" do
      expect(user.record_location_guess!(**herat, source: User::GuessSource::SEARCH_AREA)).to be(true)
      expect(user.reload).to have_attributes(guessed_source: "search_area", guessed_province: "Herat")
      expect(user.guessed_at).to be_within(5.seconds).of(Time.current)
    end

    it "lets the newest clue win" do
      user.record_location_guess!(**herat, source: User::GuessSource::LISTING)
      user.record_location_guess!(latitude: 31.6133, longitude: 65.7101, source: User::GuessSource::GPS)
      expect(user.reload).to have_attributes(guessed_province: "Kandahar", guessed_source: "gps")
    end

    it "never touches the own address, and is ignored when there is one" do
      user.update!(province: "Kabul", latitude: 34.5553, longitude: 69.2075)
      expect(user.record_location_guess!(**herat, source: User::GuessSource::LISTING)).to be(false)
      expect(user.reload).to have_attributes(guessed_latitude: nil, province: "Kabul", latitude: 34.5553)
    end

    it "ignores a point outside Afghanistan, Pakistan and Iran" do
      expect(user.record_location_guess!(latitude: 48.8566, longitude: 2.3522, source: User::GuessSource::GPS)).to be(false)
      expect(user.reload.guessed_latitude).to be_nil
    end

    it "ignores an unknown source" do
      expect(user.record_location_guess!(**herat, source: "ip")).to be(false)
    end

    it "keeps a named province only when it is one we know" do
      user.record_location_guess!(**herat, source: User::GuessSource::LISTING, province: "Nowhere")
      expect(user.reload.guessed_province).to eq("Herat")
    end
  end

  it "is wiped when the account is anonymized, own map point included" do
    user.record_location_guess!(**herat, source: User::GuessSource::LISTING)
    user.update!(latitude: 34.5553, longitude: 69.2075)
    user.anonymize_account!
    expect(user.reload).to have_attributes(guessed_latitude: nil, guessed_longitude: nil, guessed_province: nil,
                                           guessed_source: nil, guessed_at: nil, latitude: nil, longitude: nil)
  end
end
