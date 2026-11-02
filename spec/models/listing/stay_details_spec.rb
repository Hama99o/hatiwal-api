require "rails_helper"

RSpec.describe Listing::StayDetails do
  describe ".normalize" do
    it "turns form strings into integers, de-duplicates amenities and drops blanks" do
      out = described_class.normalize("guests" => "2", "beds" => "1", "amenities" => [ "wifi", "wifi", "" ], "check_in" => " 14:00 ", "bathroom" => "")
      expect(out).to eq("guests" => 2, "beds" => 1, "amenities" => [ "wifi" ], "check_in" => "14:00")
    end

    it "drops an amenities list that is only a blank (a form clearing them all)" do
      expect(described_class.normalize("amenities" => [ "" ], "guests" => "2")).to eq("guests" => 2)
    end

    it "accepts ActionController::Parameters" do
      params = ActionController::Parameters.new(guests: "3")
      expect(described_class.normalize(params)).to eq("guests" => 3)
    end
  end

  describe ".errors_for" do
    it "accepts a full, valid room" do
      details = { "guests" => 2, "beds" => 1, "bathroom" => "private", "amenities" => %w[wifi breakfast power_backup], "check_in" => "14:00", "check_out" => "11:00" }
      expect(described_class.errors_for(details)).to be_empty
    end

    it "accepts an empty hash (every key is optional — the 1.1.6 app sends none)" do
      expect(described_class.errors_for({})).to be_empty
    end

    it "refuses unknown keys, out-of-range counts, unknown amenities, bad bathroom and times" do
      errors = described_class.errors_for("stars" => 5, "guests" => 0, "beds" => "two", "amenities" => [ "pool" ], "bathroom" => "ensuite", "check_in" => "2pm")
      expect(errors.join(" | ")).to include("unknown keys: stars", "guests must be", "beds must be", "amenities must be among", "bathroom must be", "check_in must be")
    end
  end
end
