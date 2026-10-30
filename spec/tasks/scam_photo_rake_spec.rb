require "rails_helper"

# IDEA-5 (1.2.1): photos indexed before 1.2.1 have a vector but no hashes.
RSpec.describe "scam_photo rake tasks", :image_search do
  let(:corolla) { Rails.root.join("db/seeds/images/vehicles/car-corolla-1.jpg") }

  before { Rake::Task["scam_photo:backfill"].reenable }

  def listing_with_corolla(user)
    create(:listing, :active, user: user).tap do |listing|
      listing.images.attach(io: File.open(corolla), filename: "corolla.jpg", content_type: "image/jpeg")
    end
  end

  it "backfill hashes the old photos without embedding them again, then flags the newer of two accounts' same photo" do
    original = listing_with_corolla(create(:user)).tap { |l| l.update_columns(created_at: 2.days.ago) }
    copy = listing_with_corolla(create(:user))
    [ original, copy ].each { |l| embed_photo!(l, fake_vector(0)) } # 1.2.0 rows: no hashes
    allow(ImageSearch::Embedder).to receive(:embed)

    expect { Rake::Task["scam_photo:backfill"].invoke }
      .to output(/hashed=2 failed=0.*listings=2 matches=\d open_flags=1/m).to_stdout

    expect(ImageSearch::Embedder).not_to have_received(:embed)
    expect(ListingImageEmbedding.pluck(:photo_hashes)).to all(have_attributes(size: 9))
    expect(Flag.sole).to have_attributes(flaggable: copy, source: "reused_photo")
  end

  it "refuses to run when switched off" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SCAM_PHOTO_ENABLED").and_return("0")

    expect { Rake::Task["scam_photo:backfill"].invoke }.to raise_error(SystemExit)
  end
end
