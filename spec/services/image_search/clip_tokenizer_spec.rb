require "rails_helper"

# The ids must be EXACTLY those of Hugging Face `tokenizers` on the model's own
# tokenizer.json (revision 6b7c523): a single different id gives another text
# vector. The reference ids below were printed by `tokenizers` 0.23.3; every
# phrase of config/sell_photo/prompts.yml was checked the same way (141/141,
# docs/SELL_WITH_PHOTO.md §1). Needs the vocabulary files (bin/fetch-image-model).
RSpec.describe ImageSearch::ClipTokenizer do
  subject(:tokenizer) { described_class.new(*ImageSearch::TextEmbedder.tokenizer_paths) }

  before { skip("text model not fetched (bin/fetch-image-model)") unless ImageSearch::TextEmbedder.available? }

  {
    "a photo of a mobile phone" => [ 49406, 320, 1125, 539, 320, 3451, 1951, 49407 ],
    "a photo of men's clothing" => [ 49406, 320, 1125, 539, 1656, 568, 7425, 49407 ],
    "a photo of a jeweler's loupe and tweezers" => [ 49406, 320, 1125, 539, 320, 4880, 528, 568, 2207, 956, 537, 1330, 9547, 49407 ],
    "a photo of a shalwar kameez" => [ 49406, 320, 1125, 539, 320, 15056, 2238, 4104, 39033, 49407 ],
    "Phones & Tablets" => [ 49406, 6351, 261, 20436, 49407 ],
    "  Weird   SPACING, 2026! café" => [ 49406, 5613, 588, 9442, 267, 273, 271, 273, 277, 256, 15304, 49407 ],
    "ÉLAN naïve façade — Ünïcödé" => [ 49406, 3459, 4872, 1097, 35689, 563, 778, 10067, 1928, 2005, 6522, 77, 35689, 66, 7255, 67, 4166, 49407 ]
  }.each do |text, ids|
    it "encodes #{text.inspect} like Hugging Face tokenizers" do
      expect(tokenizer.encode(text)).to eq(ids)
    end
  end

  it "never goes past the model's 77 tokens (start and end included)" do
    ids = tokenizer.encode("phone " * 200)

    expect(ids.size).to eq(described_class::MAX_TOKENS)
    expect([ ids.first, ids.last ]).to eq([ described_class::START_OF_TEXT, described_class::END_OF_TEXT ])
  end
end
