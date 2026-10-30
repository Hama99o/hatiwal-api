require "rails_helper"

# IDEA-5 scam photo detection (1.2.1, hatiwal-mobile docs/design/SCAM_PHOTO.md §2): a
# transform-invariant perceptual hash. Copies of a photo — re-saved or lightly edited — are within
# MATCH_DISTANCE; a different photo, even of a look-alike product, is not. Measured on production +
# crafted copies: docs/qa-1.2.1/scam-photo/measurement/.
RSpec.describe ScamPhoto::Hasher do
  let(:seeds) { Rails.root.join("db/seeds/images") }
  let(:corolla) { File.binread(seeds.join("vehicles/car-corolla-1.jpg")) }
  let(:img) { Vips::Image.new_from_buffer(corolla, "") }

  def copy(image, format = ".jpg[Q=85]") = image.write_to_buffer(format)
  def distance(a, b) = described_class.distance(described_class.hashes(a), described_class.hashes(b))

  it "makes 9 signed 64-bit hashes (7 stored transforms + 2 query views), Postgres bigint-safe" do
    hashes = described_class.hashes(corolla)

    expect(hashes.size).to eq(9)
    expect(hashes).to all(be_between(-(2**63), (2**63) - 1))
  end

  it "the same bytes are at distance 0" do
    expect(distance(corolla, corolla)).to eq(0)
  end

  {
    "re-encoded at quality 50" => ->(i) { [ i, ".jpg[Q=50]" ] },
    "resized to 40 %" => ->(i) { [ i.resize(0.4), ".jpg[Q=85]" ] },
    "converted to WebP" => ->(i) { [ i, ".webp[Q=60]" ] },
    "mirrored" => ->(i) { [ i.fliphor, ".jpg[Q=85]" ] },
    "rotated 90°" => ->(i) { [ i.rot90, ".jpg[Q=85]" ] },
    "centre-cropped to 80 %" => ->(i) { [ i.crop((i.width * 0.1).to_i, (i.height * 0.1).to_i, (i.width * 0.8).to_i, (i.height * 0.8).to_i), ".jpg[Q=85]" ] }
  }.each do |what, make|
    it "a copy #{what} matches" do
      image, format = make.call(img)

      expect(distance(corolla, copy(image, format))).to be <= described_class::MATCH_DISTANCE
    end
  end

  it "a phone screenshot of the photo (white screen, dark status bar) matches through the trimmed view" do
    scaled = img.resize(1080.0 / img.width)
    screen = Vips::Image.black(1080, 2340, bands: 3).new_from_image([ 250, 250, 250 ]).cast(:uchar)
    screen = screen.insert(Vips::Image.black(1080, 90, bands: 3).new_from_image([ 30, 30, 30 ]).cast(:uchar), 0, 0)
    screen = screen.insert(scaled, 0, 300)

    expect(distance(corolla, copy(screen, ".png"))).to be <= described_class::MATCH_DISTANCE
  end

  it "a different photo of a look-alike product does not match (two chairs; two sedans)" do
    chair1 = File.binread(seeds.join("home/chair-1.jpg"))
    chair2 = File.binread(seeds.join("home/chair-2.jpg"))
    sedan1 = File.binread(seeds.join("vehicles/car-sedan-1.jpg"))
    sedan2 = File.binread(seeds.join("vehicles/car-sedan-2.jpg"))

    expect(distance(chair1, chair2)).to be > described_class::MATCH_DISTANCE
    expect(distance(sedan1, sedan2)).to be > described_class::MATCH_DISTANCE
  end

  it "is symmetric" do
    small = copy(img.resize(0.4))

    expect(distance(corolla, small)).to eq(distance(small, corolla))
  end

  it "refuses what is not a photo" do
    expect { described_class.hashes("not an image") }.to raise_error(ScamPhoto::Hasher::InvalidImage)
  end
end
