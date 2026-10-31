require "rails_helper"

# IDEA-9 (1.2.1): the data-saver variants travel beside today's, so an app in data-saver mode picks them and an
# older app ignores them (the v1.0.4 contract allows the additions).
RSpec.describe ListingSerializer do
  let(:listing) { create(:listing, :active, :with_image).tap { |l| l.images.attachments.first.blob.analyze } }

  before { ActiveStorage::Current.url_options = { host: "www.example.com" } }
  after { ActiveStorage::Current.url_options = nil }

  it "cards (:list, :seller_list) carry image_lite_urls" do
    %i[list seller_list].each do |view|
      hash = described_class.render_as_hash(listing, view: view)
      expect(hash[:image_lite_urls]&.size).to eq(1), view.to_s
    end
  end

  it "the detail carries image_lite_urls and image_lite_gallery_urls" do
    hash = described_class.render_as_hash(listing, view: :detailed)

    expect(hash[:image_lite_urls].size).to eq(1)
    expect(hash[:image_lite_gallery_urls].size).to eq(1)
  end
end
