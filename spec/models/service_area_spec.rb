require "rails_helper"

# Same cities as hatiwal-mobile/src/lib/__tests__/serviceArea.test.ts — the
# outline is a port, so the two must agree on every one of them.
RSpec.describe ServiceArea do
  describe ".include?" do
    {
      "Kabul" => [ 34.5553, 69.2075 ], "Herat (near the Iran border)" => [ 34.352, 62.204 ],
      "Islam Qala border crossing" => [ 34.66, 61.07 ], "Mazar-i-Sharif" => [ 36.709, 67.11 ],
      "Wakhan corridor" => [ 37.0, 73.5 ], "Jalalabad" => [ 34.43, 70.45 ], "Torkham" => [ 34.11, 71.09 ],
      "Peshawar" => [ 34.0, 71.57 ], "Islamabad" => [ 33.684, 73.048 ], "Lahore" => [ 31.55, 74.34 ],
      "Karachi" => [ 24.86, 67.0 ], "Quetta" => [ 30.18, 66.97 ], "Gilgit" => [ 35.92, 74.31 ],
      "Tehran" => [ 35.69, 51.39 ], "Mashhad" => [ 36.3, 59.6 ], "Zahedan" => [ 29.5, 60.86 ],
      "Tabriz" => [ 38.08, 46.29 ], "Bandar Abbas" => [ 27.18, 56.27 ], "Ahvaz" => [ 31.32, 48.67 ],
      "Gwadar" => [ 25.12, 62.32 ], "Chabahar" => [ 25.29, 60.64 ], "Jiwani" => [ 25.05, 61.75 ],
      "Sarakhs" => [ 36.54, 61.16 ], "Bajgiran" => [ 37.61, 58.41 ], "Astara (Iran)" => [ 38.43, 48.87 ],
      "Hairatan" => [ 37.22, 67.42 ], "Sialkot" => [ 32.49, 74.53 ], "Wagah (Pakistan side)" => [ 31.6, 74.55 ]
    }.each do |name, (lat, lng)|
      it("#{name} is inside") { expect(described_class.include?(lat, lng)).to be(true) }
    end

    {
      "Paris" => [ 48.8566, 2.3522 ], "Dubai" => [ 25.2, 55.27 ], "Doha" => [ 25.29, 51.53 ],
      "Kuwait City" => [ 29.37, 47.98 ], "Baghdad" => [ 33.31, 44.36 ], "Istanbul" => [ 41.0, 28.98 ],
      "Ashgabat" => [ 37.95, 58.38 ], "Tashkent" => [ 41.3, 69.24 ], "Dushanbe" => [ 38.56, 68.77 ],
      "Delhi" => [ 28.61, 77.2 ], "Amritsar" => [ 31.63, 74.87 ], "Muscat" => [ 23.59, 58.4 ],
      "Gulf of Guinea (0,0)" => [ 0, 0 ]
    }.each do |name, (lat, lng)|
      it("#{name} is outside") { expect(described_class.include?(lat, lng)).to be(false) }
    end

    it "rejects missing or broken coordinates" do
      expect(described_class.include?(nil, 69)).to be(false)
      expect(described_class.include?("abc", 69)).to be(false)
      expect(described_class.include?(Float::NAN, 69)).to be(false)
    end

    it "accepts the decimal strings the API stores" do
      expect(described_class.include?("34.555300", "69.207500")).to be(true)
    end
  end

  describe ".province_in_text" do
    it("reads the first part of a listing location") { expect(described_class.province_in_text("Herat, City Center")).to eq("Herat") }
    it("is nil for an unknown place") { expect(described_class.province_in_text("Shahr-e-Naw")).to be_nil }
  end

  describe ".nearest_province" do
    it("names the province around a point") { expect(described_class.nearest_province(34.36, 62.21)).to eq("Herat") }
    it("names nothing for a point far from every capital (Tehran)") { expect(described_class.nearest_province(35.69, 51.39)).to be_nil }
  end
end
