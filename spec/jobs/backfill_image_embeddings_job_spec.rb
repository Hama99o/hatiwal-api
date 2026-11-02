require "rails_helper"

RSpec.describe BackfillImageEmbeddingsJob, :image_search, type: :job do
  include ActiveJob::TestHelper

  before { allow(ImageSearch::Embedder).to receive(:embed).and_return(fake_vector(0)) }

  # Photos attached BEFORE the feature: no job ran for them.
  def old_listing(trait = :active)
    Rails.configuration.x.image_search_enabled = false
    create(:listing, trait, :with_image).tap { Rails.configuration.x.image_search_enabled = true }
  end

  it "embeds every listing photo without a vector, whatever the listing's status" do
    listings = [ old_listing, old_listing(:draft), old_listing(:sold) ]

    expect { described_class.perform_now }.to change(ListingImageEmbedding, :count).by(3)
    expect(ListingImageEmbedding.pluck(:listing_id)).to match_array(listings.map(&:id))
  end

  it "skips photos that already have a vector of today's model" do
    listing = old_listing
    embed_photo!(listing, fake_vector(1))

    expect { described_class.perform_now }.not_to change(ListingImageEmbedding, :count)
    expect(ImageSearch::Embedder).not_to have_received(:embed)
  end

  it "re-embeds photos whose only vector is from another model version" do
    listing = old_listing
    ListingImageEmbedding.create!(listing: listing, attachment: listing.images.attachments.first,
                                  model_version: "an-older-model", vector: fake_vector(1))

    expect { described_class.perform_now }.to change { ListingImageEmbedding.current_model.count }.by(1)
  end

  it "never touches avatars" do
    create(:user).avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                                filename: "a.jpg", content_type: "image/jpeg")

    described_class.perform_now
    expect(ImageSearch::Embedder).not_to have_received(:embed)
  end

  it "works in batches, each enqueueing the next after its last photo" do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    3.times { old_listing }
    ids = ActiveStorage::Attachment.where(record_type: Listing.name).order(:id).ids

    embedded, failed, last_id = described_class.perform_now

    expect([ embedded, failed, last_id ]).to eq([ 2, 0, ids[1] ])
    expect(described_class).to have_been_enqueued.with(ids[1])
    perform_enqueued_jobs
    expect(ListingImageEmbedding.count).to eq(3)
  end

  it "skips a photo it cannot read and goes on with the others" do
    old_listing
    old_listing
    calls = 0
    allow(ImageSearch::Embedder).to receive(:embed) do
      calls += 1
      calls == 1 ? raise(ImageSearch::Embedder::InvalidImage, "bad") : fake_vector(0)
    end

    embedded, failed, = described_class.perform_now
    expect([ embedded, failed ]).to eq([ 1, 1 ])
  end
end
