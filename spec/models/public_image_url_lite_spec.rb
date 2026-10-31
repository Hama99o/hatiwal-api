require "rails_helper"

# IDEA-9 (1.2.1, docs/design/DATA_SAVER_AND_RESUMABLE_UPLOAD.md §2–3): the data-saver variants. On the 44
# production photos (docs/qa-1.2.1/datasaver/measurement/): a card thumb (640, WebP q80) is 37 KB median, the
# lite card (320, q60) 11 KB — a Bazaar page of 20 cards 978 KB -> 227 KB (-77 %); the gallery's medium (1440)
# 70 KB, the lite gallery (720, q60) 19 KB.
RSpec.describe PublicImageUrl do
  # A real photo (the 1 px test image makes every variant the same few bytes).
  let(:listing) do
    create(:listing, :active).tap do |l|
      l.images.attach(io: File.open(Rails.root.join("db/seeds/images/vehicles/car-corolla-1.jpg")), filename: "c.jpg", content_type: "image/jpeg")
    end
  end
  let(:photo) { listing.images.attachments.first.tap { |a| a.blob.analyze } }

  before { ActiveStorage::Current.url_options = { host: "www.example.com" } }
  after { ActiveStorage::Current.url_options = nil }

  it "lite: short side 320 (long ≤ 800), WebP q60, stripped — smaller than the thumb" do
    expect(described_class::SIZES[:lite]).to eq([ 320, 800 ])
    expect(described_class::SIZES[:lite_gallery]).to eq([ 720, 720 ])

    lite = photo.variant(resize_to_limit: described_class.box(photo.blob, :lite), format: :webp, saver: described_class::LITE_SAVER).processed
    thumb = photo.variant(resize_to_limit: described_class.box(photo.blob, :thumb), format: :webp, saver: described_class::SAVER).processed
    image = Vips::Image.new_from_buffer(lite.download, "")
    expect([ image.width, image.height ].min).to be <= 320
    expect(lite.download.bytesize).to be < thumb.download.bytesize
    expect(described_class.variant(photo, :lite)).to include("/representations/")
  end

  it "the listing's lite card and gallery urls, one per photo, in the photos' order" do
    photo
    expect(listing.image_lite_urls.size).to eq(1)
    expect(listing.image_lite_gallery_urls.size).to eq(1)
    expect(listing.image_lite_urls.first).to include("/representations/")
  end
end
