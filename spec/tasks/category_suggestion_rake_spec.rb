require "rails_helper"

# Sell with a photo (docs/SELL_WITH_PHOTO.md §4): after a deploy, the category
# vectors are built ONCE into the shared cache (solid_cache in production), so
# the first seller does not wait ~6 s.
RSpec.describe "category_suggestion rake tasks", :image_search do
  let(:shared_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    CategorySuggestion.reset!
    allow(Rails).to receive(:cache).and_return(shared_cache)
    allow(ImageSearch::TextEmbedder).to receive(:available?).and_return(true)
    allow(ImageSearch::TextEmbedder).to receive(:embed_all) { |phrases| phrases.map { fake_vector(0) } }
    Rake::Task["category_suggestion:warm"].reenable
  end

  after { CategorySuggestion.reset! }

  it "warm builds every slug's vector into the shared cache; a fresh process then reuses it" do
    expect { Rake::Task["category_suggestion:warm"].invoke }
      .to output(/category_suggestion:warm #{CategorySuggestion.prompts.size} categories ready/).to_stdout

    CategorySuggestion.reset! # another Puma worker: nothing in its own memory
    CategorySuggestion.call(fake_vector(0))
    expect(ImageSearch::TextEmbedder).to have_received(:embed_all).once
  end

  it "warm refuses to run without the text model" do
    allow(ImageSearch::TextEmbedder).to receive(:available?).and_return(false)

    expect { Rake::Task["category_suggestion:warm"].invoke }.to raise_error(SystemExit).and output(/text model missing/).to_stderr
  end
end
