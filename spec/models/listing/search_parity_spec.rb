require "rails_helper"

# OFFLINE §4.8 (docs/OFFLINE_MODE.md): the app searches the listings already on
# the phone when it is offline, and must give the SAME results as this method.
# Both sides run ONE fixture: spec/fixtures/files/search_parity.json here, and a
# byte-identical copy in hatiwal-mobile src/lib/offline/__fixtures__/ (run by
# localSearch.test.ts). A change to Listing.search that breaks a case here must
# change the phone's copy of the rules too.
RSpec.describe Listing, type: :model do
  fixture = JSON.parse(Rails.root.join("spec/fixtures/files/search_parity.json").read)

  let!(:ids) do
    fixture["listings"].to_h do |row|
      listing = create(:listing, title: row["title"], description: row["description"])
      [ row["id"], listing.id ]
    end
  end

  fixture["cases"].each do |c|
    it "Listing.search(#{c['query'].inspect}) → fixture #{c['expect'].inspect}" do
      found = described_class.where(id: ids.values).search(c["query"]).pluck(:id)
      expected = c["expect"].map { |fixture_id| ids.fetch(fixture_id) }
      expect(found).to match_array(expected)
    end
  end

  it "caps the words at 10 like the app (MAX_SEARCH_WORDS)" do
    expect(described_class::MAX_SEARCH_WORDS).to eq(10)
  end
end
