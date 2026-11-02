require "rails_helper"

# UPD-1 — the comparison table; hatiwal-mobile/src/lib/__tests__/appVersion.test.ts
# runs the SAME rows, so server and app agree.
RSpec.describe AppVersion do
  [
    [ "1.1.5", "1.1.6", -1 ], [ "1.1.6", "1.1.6", 0 ], [ "1.1.7", "1.1.6", 1 ],
    [ "1.10.0", "1.9.9", 1 ], [ "1.9", "1.10", -1 ], [ "2", "1.99.99", 1 ],
    [ "1.1", "1.1.0", 0 ], [ "1.1.0.1", "1.1", 1 ], [ "0.9.9", "1.0", -1 ]
  ].each do |a, b, expected|
    it("#{a} vs #{b} → #{expected}") { expect(described_class.compare(a, b)).to eq(expected) }
  end

  [ nil, "", "abc", "1..2", "1.2.3.4.5", "v1.2", " 1.2", "1.2-beta" ].each do |bad|
    it("treats #{bad.inspect} as not a version") do
      expect(described_class.compare(bad, "1.0")).to be_nil unless bad == " 1.2"
      expect(described_class.below?(bad, "9.9")).to be(false) unless bad == " 1.2"
    end
  end
end
