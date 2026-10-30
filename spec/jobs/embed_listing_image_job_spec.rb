require "rails_helper"

RSpec.describe EmbedListingImageJob, :image_search, type: :job do
  include ActiveJob::TestHelper

  let(:listing) { create(:listing, :active, :with_image) }
  let(:photo)   { listing.images.attachments.first }

  before { allow(ImageSearch::Embedder).to receive(:embed).and_return(fake_vector(0)) }

  it "stores the vector of a listing photo, with today's model version" do
    expect { described_class.perform_now(photo.id) }.to change(ListingImageEmbedding, :count).by(1)

    row = ListingImageEmbedding.last
    expect([ row.listing_id, row.attachment_id, row.model_version ])
      .to eq([ listing.id, photo.id, ImageSearch::Embedder::MODEL_VERSION ])
    expect(row.vector).to eq(fake_vector(0))
  end

  # IDEA-5 (1.2.1): the same read of the photo also stores its 9 perceptual hashes, then the
  # listing is matched against other accounts' photos (ScamPhotoMatchJob).
  it "stores the photo's perceptual hashes and queues the scam-photo matcher for the listing" do
    expect { described_class.perform_now(photo.id) }.to have_enqueued_job(ScamPhotoMatchJob).with(listing.id)

    expect(ListingImageEmbedding.last.photo_hashes)
      .to eq(ScamPhoto::Hasher.hashes(File.binread(Rails.root.join("spec/fixtures/files/test_image.jpg"))))
  end

  it "hashes a photo embedded before 1.2.1 (row without hashes) without embedding it again" do
    embed_photo!(listing, fake_vector(0), attachment: photo)

    expect { described_class.perform_now(photo.id) }.to have_enqueued_job(ScamPhotoMatchJob).with(listing.id)
    expect(ListingImageEmbedding.sole.photo_hashes.size).to eq(9)
    expect(ImageSearch::Embedder).not_to have_received(:embed)
  end

  it "does nothing the second time" do
    described_class.perform_now(photo.id)

    expect { described_class.perform_now(photo.id) }.not_to change(ListingImageEmbedding, :count)
    expect(ImageSearch::Embedder).to have_received(:embed).once
  end

  it "does nothing for a photo deleted before the job ran" do
    id = photo.id
    photo.destroy

    expect { described_class.perform_now(id) }.not_to change(ListingImageEmbedding, :count)
  end

  it "never embeds anything but a listing photo (an avatar here)" do
    user = create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                       filename: "a.jpg", content_type: "image/jpeg")

    expect { described_class.perform_now(user.avatar.attachment.id) }.not_to change(ListingImageEmbedding, :count)
    expect(ImageSearch::Embedder).not_to have_received(:embed)
  end

  it "drops a photo the decoder cannot read, without retrying" do
    allow(ImageSearch::Embedder).to receive(:embed).and_raise(ImageSearch::Embedder::InvalidImage, "bad")

    photo
    expect { described_class.perform_now(photo.id) }.not_to have_enqueued_job(described_class)
    expect(ListingImageEmbedding.count).to eq(0)
  end

  describe "enqueued when a photo is added" do
    it "for a new listing photo" do
      listing
      expect do
        listing.images.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                              filename: "b.jpg", content_type: "image/jpeg")
      end.to have_enqueued_job(described_class).on_queue("image_embeddings")
    end

    it "never for an avatar" do
      user = create(:user)
      expect do
        user.avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                           filename: "a.jpg", content_type: "image/jpeg")
      end.not_to have_enqueued_job(described_class)
    end

    it "never while search by image is off" do
      Rails.configuration.x.image_search_enabled = false
      expect { listing }.not_to have_enqueued_job(described_class)
    end
  end
end

RSpec.describe EmbedListingImageJob, type: :job do
  it "is not enqueued for the rest of the suite (search by image is off in tests)" do
    expect { create(:listing, :active, :with_image) }.not_to have_enqueued_job(described_class)
  end
end
