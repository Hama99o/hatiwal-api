require "rails_helper"

RSpec.describe "image_search rake tasks", :image_search do
  before do
    allow(ImageSearch::Embedder).to receive(:embed).and_return(fake_vector(0))
    Rake::Task["image_search:backfill"].reenable
    Rake::Task["image_search:stats"].reenable
  end

  it "backfill embeds every listing photo still without a vector, batch after batch" do
    stub_const("BackfillImageEmbeddingsJob::BATCH_SIZE", 1)
    Rails.configuration.x.image_search_enabled = false
    create_list(:listing, 2, :active, :with_image)
    Rails.configuration.x.image_search_enabled = true

    expect { Rake::Task["image_search:backfill"].invoke }
      .to output(/embedded=2 failed=0 after_id=done/).to_stdout
    expect(ListingImageEmbedding.current_model.count).to eq(2)
  end

  it "stats counts the photos and their vectors" do
    listing = create(:listing, :active, :with_image)
    embed_photo!(listing, fake_vector(0))

    expect { Rake::Task["image_search:stats"].invoke }.to output(/listing photos=1 embedded\(.+\)=1/).to_stdout
  end
end
