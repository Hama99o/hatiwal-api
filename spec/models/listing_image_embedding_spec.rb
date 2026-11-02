require "rails_helper"

RSpec.describe ListingImageEmbedding, type: :model do
  let(:listing) { create(:listing, :active, :with_image) }
  let(:photo)   { listing.images.attachments.first }

  def build_row(**attrs)
    described_class.new(listing: listing, attachment: photo,
                        model_version: ImageSearch::Embedder::MODEL_VERSION, vector: fake_vector(0), **attrs)
  end

  it "packs the vector into 4 bytes per number and reads it back" do
    row = build_row
    row.save!

    expect(row.reload.embedding.bytesize).to eq(ImageSearch::Embedder::DIMENSIONS * 4)
    expect(row.vector).to eq(fake_vector(0))
  end

  it "refuses a vector of the wrong size, and a row without a model version" do
    expect(build_row(vector: [ 1.0, 0.0 ])).not_to be_valid
    expect(build_row(model_version: nil)).not_to be_valid
  end

  it "keeps one row per photo and model version" do
    build_row.save!

    expect { build_row.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "goes away with its photo" do
    build_row.save!

    expect { photo.destroy }.to change(described_class, :count).by(-1)
  end

  it "goes away with its listing" do
    build_row.save!

    expect { listing.destroy }.to change(described_class, :count).by(-1)
  end
end
