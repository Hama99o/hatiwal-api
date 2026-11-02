require "rails_helper"

# Runs the REAL CLIP model (:image_model): skipped, with a reason, on a machine
# where bin/fetch-image-model has not been run.
RSpec.describe ImageSearch::Embedder, :image_search, :image_model do
  def seed_photo(name) = File.binread(Rails.root.join("db/seeds/images", name))
  def cosine(a, b) = a.zip(b).sum { |x, y| x * y }

  it "turns a photo into a unit-length vector of the model's size" do
    vector = described_class.embed(seed_photo("vehicles/car-corolla-1.jpg"))

    expect(vector.size).to eq(described_class::DIMENSIONS)
    expect(Math.sqrt(vector.sum { |x| x * x })).to be_within(1e-5).of(1.0)
  end

  it "gives the same vector for the same photo" do
    bytes = seed_photo("home/sofa-1.jpg")

    expect(cosine(described_class.embed(bytes), described_class.embed(bytes))).to be > 0.9999
  end

  it "puts another photo of the same kind of thing closer than a different thing" do
    car = described_class.embed(seed_photo("vehicles/car-corolla-1.jpg"))
    other_car = described_class.embed(seed_photo("vehicles/car-corolla-2.jpg"))
    sofa = described_class.embed(seed_photo("home/sofa-1.jpg"))

    expect(cosine(car, other_car)).to be > cosine(car, sofa)
  end

  it "finds a re-shot (cropped, mirrored, re-encoded) photo very close to the original" do
    original = Vips::Image.new_from_buffer(seed_photo("home/chair-1.jpg"), "")
    reshot = original.crop(original.width / 10, original.height / 10, original.width * 8 / 10, original.height * 8 / 10)
                     .fliphor.webpsave_buffer(Q: 60)

    expect(cosine(described_class.embed(seed_photo("home/chair-1.jpg")), described_class.embed(reshot))).to be > 0.85
  end

  it "reads PNGs with transparency and greyscale photos" do
    chair = Vips::Image.new_from_buffer(seed_photo("home/chair-1.jpg"), "")
    rgba = chair.bandjoin(128).pngsave_buffer
    grey = chair.colourspace(:b_w).jpegsave_buffer

    expect(described_class.embed(rgba).size).to eq(described_class::DIMENSIONS)
    expect(described_class.embed(grey).size).to eq(described_class::DIMENSIONS)
  end

  # iPhone photos are HEIC (HEVC). The apps re-encode to JPEG before sending, but the web may send
  # one as it is. The fixture is db/seeds/images/vehicles/car-corolla-1.jpg (CC0) at 480 px,
  # encoded with heif-enc (x265). libvips decodes it through libheif's HEVC plugin, a hard
  # dependency of the Debian libheif1 package, so the production image has it too.
  it "reads an iPhone HEIC photo, close to the same photo as a JPEG" do
    heic = File.binread(Rails.root.join("spec/fixtures/files/car-corolla-1.heic"))

    expect(cosine(described_class.embed(heic), described_class.embed(seed_photo("vehicles/car-corolla-1.jpg")))).to be > 0.95
  end

  it "refuses bytes that are not a photo, and an empty file" do
    expect { described_class.embed(File.binread(Rails.root.join("spec/fixtures/files/not_an_image.zip"))) }
      .to raise_error(described_class::InvalidImage)
    expect { described_class.embed("") }.to raise_error(described_class::InvalidImage)
  end

  it "refuses a truncated photo" do
    expect { described_class.embed(seed_photo("home/chair-1.jpg").byteslice(0, 2_000)) }
      .to raise_error(described_class::InvalidImage)
  end

  it "loads the model once per process, however many threads embed at the same time" do
    bytes = seed_photo("home/chair-2.jpg")
    expect(OnnxRuntime::InferenceSession).not_to receive(:new) if described_class.loaded?

    vectors = Array.new(4) { Thread.new { described_class.embed(bytes) } }.map(&:value)

    expect(vectors.map { |v| v.map { |x| x.round(5) } }.uniq.size).to eq(1)
  end
end

RSpec.describe ImageSearch::Embedder, :image_search do
  it "refuses a blank photo (a covered lens) before it reaches the model" do
    white = Vips::Image.black(640, 480).new_from_image([ 250, 250, 250 ]).copy(interpretation: :srgb).jpegsave_buffer
    black = Vips::Image.black(640, 480).copy(interpretation: :srgb).bandjoin([ 0, 0 ]).jpegsave_buffer

    expect { described_class.pixel_values(white) }.to raise_error(described_class::PlainImage)
    expect { described_class.pixel_values(black) }.to raise_error(described_class::PlainImage)
    expect(described_class::PlainImage.ancestors).to include(described_class::InvalidImage)
  end

  it "is unavailable (and raises, never downloads) when the model file is missing" do
    allow(described_class).to receive(:available?).and_call_original
    allow(described_class).to receive(:model_dir).and_return(Rails.root.join("tmp/no-model-here").to_s)
    described_class.instance_variable_set(:@session, nil)

    expect(described_class.available?).to be false
    expect { described_class.embed(File.binread(Rails.root.join("spec/fixtures/files/test_image.jpg"))) }
      .to raise_error(described_class::Unavailable)
  ensure
    described_class.instance_variable_set(:@session, nil)
  end
end
