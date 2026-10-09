require "rails_helper"

# The dev/demo seed's photos (2026-10-09): committed CC0 files, never the network,
# and never a 0-byte image (the old loremflickr seed left 75 of 116 listings
# photo-less, and an e2e reset left blobs whose files were gone).
RSpec.describe SeedPhotos do
  let(:files) { Dir[SeedPhotos::DIR.join("*/*.jpg").to_s].sort }
  let(:readme) { SeedPhotos::DIR.join("README.md").read }

  describe "the committed files" do
    it "exist, are non-empty JPEGs no larger than 1600 px, each with its source in the README" do
      expect(files).not_to be_empty
      files.each do |f|
        rel = f.delete_prefix("#{SeedPhotos::DIR}/")
        expect(File.size(f)).to be_between(1, 300_000), "#{rel}: #{File.size(f)} bytes"
        expect(File.binread(f, 2).bytes).to eq([ 0xFF, 0xD8 ]), "#{rel} is not a JPEG"
        image = Vips::Image.new_from_file(f)
        expect([ image.width, image.height ].max).to be <= 1600, rel
        expect(readme).to include("`#{rel}`"), "#{rel} has no row (source) in db/seeds/images/README.md"
      end
    end

    it "has no README row without its file" do
      rows = readme.scan(/^\| `([^`]+)` \|/).flatten
      expect(rows.map { |r| SeedPhotos::DIR.join(r).to_s } - files).to eq([])
    end
  end

  describe ".attach!" do
    let(:vehicles) { Category.find_by(slug: "vehicles") || create(:category, slug: "vehicles") }
    let(:cars) { create(:category, parent: vehicles, slug: "cars-#{SecureRandom.hex(3)}") }
    let(:listing) { create(:listing, category: cars, title: "Toyota Corolla 2015 Low Mileage") }

    it "attaches photos of the listing's TOP-LEVEL category, title matches first, every one with bytes" do
      expect(described_class.attach!(listing)).to eq(:attached)

      blobs = listing.reload.images.map(&:blob)
      expect(blobs.size).to eq(3)
      expect(blobs).to all(satisfy { |b| b.byte_size.positive? && b.service.exist?(b.key) })
      expect(blobs.first(2).map { |b| b.filename.to_s }).to all(start_with("car-corolla-"))
    end

    it "uses the seed's keyword hint too" do
      bike = create(:listing, category: cars, title: "Honda CG 125 2021")
      described_class.attach!(bike, hint: "motorcycle,motorbike")
      expect(bike.reload.images.first.blob.filename.to_s).to start_with("motorcycle-")
    end

    it "keeps healthy photos, and re-attaches when a photo's file is gone from storage" do
      described_class.attach!(listing)
      expect(described_class.attach!(listing.reload)).to eq(:kept)

      gone = listing.images.first.blob
      gone.service.delete(gone.key)
      expect(described_class.attach!(listing.reload)).to eq(:attached)
      expect(described_class.healthy?(listing.reload)).to be(true)
    end

    it "leaves a listing of a category without fixtures alone" do
      other = create(:listing, category: create(:category, slug: "no-photos-#{SecureRandom.hex(3)}"))
      expect(described_class.attach!(other)).to eq(:no_fixtures)
    end

    it "raises on an empty fixture instead of attaching a 0-byte image" do
      empty = Rails.root.join("tmp/empty-seed-photo.jpg")
      File.write(empty, "")
      allow(described_class).to receive(:files_for).and_return([ empty.to_s ])
      expect { described_class.attach!(listing) }.to raise_error(SeedPhotos::BadFixture, /missing or empty/)
    ensure
      FileUtils.rm_f(empty)
    end
  end
end
