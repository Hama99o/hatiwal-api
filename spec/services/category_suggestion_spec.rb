require "rails_helper"

# Sell with a photo (docs/SELL_WITH_PHOTO.md). The text model is stubbed: every
# phrase of a category points along that category's own axis, so a photo
# vector built with fake_vector says exactly which category it "shows". The
# real model is covered at the end (:image_model).
RSpec.describe CategorySuggestion, :image_search do
  let(:electronics) { create(:category, slug: "electronics") }
  let!(:phones)     { create(:category, slug: "phones", parent: electronics) }
  let!(:cars)       { create(:category, slug: "cars", parent: create(:category, slug: "vehicles")) }
  let(:axes)        { { "phones" => 0, "cars" => 1, "skincare" => 2, "other" => 3 } }

  before do
    described_class.reset!
    allow(ImageSearch::TextEmbedder).to receive(:available?).and_return(true)
    allow(ImageSearch::TextEmbedder).to receive(:embed_all) do |phrases|
      phrases.map do |phrase|
        slug = described_class.prompts.find { |_slug, list| list.include?(phrase) }&.first
        fake_vector(axes.fetch(slug, 9))
      end
    end
  end

  after { described_class.reset! }

  it "suggests the category the photo shows, with its parent and the confidence" do
    result = described_class.call(fake_vector(0))

    expect(result).to have_attributes(category_id: phones.id, parent_id: electronics.id)
    expect(result.confidence).to be > 0.99
  end

  it "suggests nothing when no category is likely enough (three-way tie: 1/3 < MIN_CONFIDENCE)" do
    create(:category, slug: "skincare")
    tie = Array.new(ImageSearch::Embedder::DIMENSIONS, 0.0)
    (0..2).each { |axis| tie[axis] = Math.sqrt(1.0 / 3) }

    expect(described_class.call(tie)).to be_nil
  end

  it "only suggests ACTIVE categories, and a switched-off one does not hand its photos to another" do
    phones.update!(active: false)

    # Not "cars": phones still wins the vote, then is not offered.
    expect(described_class.call(fake_vector(0))).to be_nil
  end

  it "never suggests a category without prompts (Other, Property, Jobs, Services, Stays)" do
    create(:category, slug: "other")
    expect(described_class.prompts).not_to have_key("other")

    result = described_class.call(fake_vector(3))
    expect(result&.category_id).not_to eq(Category.find_by(slug: "other").id)
  end

  it "embeds the prompts once, then reuses the vectors" do
    3.times { described_class.call(fake_vector(0)) }

    expect(ImageSearch::TextEmbedder).to have_received(:embed_all).once
  end

  it "suggests a category switched on later, without embedding the prompts again" do
    described_class.call(fake_vector(0))
    skincare = create(:category, slug: "skincare")

    expect(described_class.call(fake_vector(2))&.category_id).to eq(skincare.id)
    expect(ImageSearch::TextEmbedder).to have_received(:embed_all).once
  end

  it "suggests nothing when no category can be suggested" do
    Category.update_all(active: false)

    expect(described_class.call(fake_vector(0))).to be_nil
  end

  describe ".enabled?" do
    it "is true with both halves of the model" do
      expect(described_class.enabled?).to be true
    end

    it "is false without the text model" do
      allow(ImageSearch::TextEmbedder).to receive(:available?).and_return(false)
      expect(described_class.enabled?).to be false
    end

    it "is false when search by image is off (no image model, or its kill switch)" do
      allow(ImageSearch).to receive(:enabled?).and_return(false)
      expect(described_class.enabled?).to be false
    end

    it "is false with its own kill switch CATEGORY_SUGGESTION_ENABLED=0" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CATEGORY_SUGGESTION_ENABLED").and_return("0")
      expect(described_class.enabled?).to be false
    end
  end

  describe "with the real model", :image_model do
    before do
      skip("text model not fetched (bin/fetch-image-model)") unless ImageSearch::TextEmbedder.available?
      allow(ImageSearch::TextEmbedder).to receive(:embed_all).and_call_original
      create(:category, slug: "furniture")
      create(:category, slug: "shoes")
    end

    def suggestion_for(seed_photo)
      vector = ImageSearch::Embedder.embed(File.binread(Rails.root.join("db/seeds/images", seed_photo)))
      described_class.call(vector)&.category_id
    end

    it "recognises a car, a sofa and a pair of shoes" do
      expect(suggestion_for("vehicles/car-corolla-1.jpg")).to eq(cars.id)
      expect(suggestion_for("home/sofa-2.jpg")).to eq(Category.find_by(slug: "furniture").id)
      expect(suggestion_for("clothes/shoes-2.jpg")).to eq(Category.find_by(slug: "shoes").id)
    end
  end
end
