require "rails_helper"

RSpec.describe ImageSearch::Search, :image_search do
  let(:phones) { create(:category, name_en: "Phones") }
  let(:cars)   { create(:category, name_en: "Cars") }

  def listing_with_vector(vector, category: phones, **attrs)
    listing = create(:listing, :active, :with_image, category: category, **attrs)
    embed_photo!(listing, vector)
    listing
  end

  def search(vector, scope = Listing.browsable) = described_class.call(vector, scope)

  it "ranks listings by how close their photo is, best first" do
    far  = listing_with_vector(fake_vector(0, other: 1, mix: 0.3))
    near = listing_with_vector(fake_vector(0, other: 1, mix: 0.05))

    expect(search(fake_vector(0)).map(&:listing_id)).to eq([ near.id, far.id ])
  end

  it "scores a listing by its BEST photo" do
    listing = listing_with_vector(fake_vector(5))
    listing.images.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                          filename: "b.jpg", content_type: "image/jpeg")
    embed_photo!(listing, fake_vector(0), attachment: listing.reload.images.attachments.max_by(&:id))

    result = search(fake_vector(0)).sole
    expect(result.listing_id).to eq(listing.id)
    expect(result.image_score).to be_within(1e-6).of(1.0)
  end

  it "leaves out everything under the minimum score" do
    listing_with_vector(fake_vector(0, other: 1, mix: 1.0 - (0.55**2)))  # cosine 0.55
    kept = listing_with_vector(fake_vector(0, other: 1, mix: 1.0 - (0.65**2)))  # cosine 0.65

    expect(search(fake_vector(0)).map(&:listing_id)).to eq([ kept.id ])
  end

  it "returns nothing when no photo is close enough" do
    listing_with_vector(fake_vector(1))

    expect(search(fake_vector(0))).to eq([])
  end

  it "boosts the category most of the best matches agree on, past a slightly closer outsider" do
    outsider = listing_with_vector(fake_vector(0, other: 1, mix: 1.0 - (0.82**2)), category: cars)
    phone_a  = listing_with_vector(fake_vector(0, other: 1, mix: 1.0 - (0.80**2)))
    phone_b  = listing_with_vector(fake_vector(0, other: 2, mix: 1.0 - (0.79**2)))
    phone_c  = listing_with_vector(fake_vector(0, other: 3, mix: 1.0 - (0.78**2)))

    results = search(fake_vector(0))
    expect(results.map(&:listing_id)).to eq([ phone_a.id, phone_b.id, outsider.id, phone_c.id ])
    expect(results.first.score).to be_within(1e-6).of(0.80 + described_class::CATEGORY_BOOST)
    expect(results.first.image_score).to be_within(1e-6).of(0.80)
  end

  it "counts a subcategory as its top-level category in the vote" do
    android = create(:category, name_en: "Android", parent: phones)
    listing_with_vector(fake_vector(0, other: 1, mix: 1.0 - (0.80**2)))
    sub = listing_with_vector(fake_vector(0, other: 2, mix: 1.0 - (0.70**2)), category: android)

    expect(search(fake_vector(0)).find { |r| r.listing_id == sub.id }.score)
      .to be_within(1e-6).of(0.70 + described_class::CATEGORY_BOOST)
  end

  it "boosts nothing when no category holds most of the votes" do
    listing_with_vector(fake_vector(0, other: 1, mix: 1.0 - (0.80**2)), category: cars)
    listing_with_vector(fake_vector(0, other: 2, mix: 1.0 - (0.79**2)))
    listing_with_vector(fake_vector(0, other: 3, mix: 1.0 - (0.78**2)), category: create(:category, name_en: "Sofas"))

    results = search(fake_vector(0))
    expect(results.size).to eq(3)
    expect(results.map(&:score)).to eq(results.map(&:image_score))
  end

  it "searches only the listings of the scope it is given" do
    inside  = listing_with_vector(fake_vector(0))
    outside = listing_with_vector(fake_vector(0), category: cars)

    expect(search(fake_vector(0), Listing.browsable.where(category: phones)).map(&:listing_id)).to eq([ inside.id ])
    expect(outside).to be_persisted
  end

  it "ignores vectors of another model version" do
    listing = create(:listing, :active, :with_image, category: phones)
    ListingImageEmbedding.create!(listing: listing, attachment: listing.images.attachments.first,
                                  model_version: "an-older-model", vector: fake_vector(0))

    expect(search(fake_vector(0))).to eq([])
  end

  it "returns at most MAX_RESULTS" do
    stub_const("#{described_class}::MAX_RESULTS", 2)
    3.times { listing_with_vector(fake_vector(0)) }

    expect(search(fake_vector(0)).size).to eq(2)
  end
end
