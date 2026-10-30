require "rails_helper"

# IDEA-8 (1.2.1): the link-preview image (og:image) — WhatsApp drops large images, and production
# served the 4096 px q90 photo (1.1 MB measured on listing 76). The share variant is a 1200 × 630
# cover crop, JPEG q80, stripped: 44 production photos measured ≤ 177 KB (docs/qa-1.2.1/share-qr/).
RSpec.describe PublicImageUrl do
  let(:listing) { create(:listing, :active, :with_image) }
  let(:photo) { listing.images.attachments.first.tap { |a| a.blob.analyze } }

  # Variants are only built for an analysed photo (PublicImageUrl.processable?), with the request's host.
  before { ActiveStorage::Current.url_options = { host: "www.example.com" } }
  after { ActiveStorage::Current.url_options = nil }

  it "share: a stable representation URL of a 1200 × 630 JPEG, without the photo's metadata" do
    url = described_class.share(photo)

    expect(url).to include("/rails/active_storage/representations/redirect/")
    variant = photo.variant(described_class::SHARE)
    file = Vips::Image.new_from_buffer(variant.processed.download, "")
    expect([ file.width, file.height ]).to eq([ 1200, 630 ])
    expect(variant.processed.download.byteslice(0, 2)).to eq("\xFF\xD8".b)
    expect(file.get_fields).not_to include("exif-data")
  end

  it "share: nil without a photo" do
    expect(described_class.share(nil)).to be_nil
  end

  it "the listing's and the shop's share image" do
    shop = create(:shop)
    shop.cover.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "c.jpg", content_type: "image/jpeg")
    shop.cover.blob.analyze

    photo
    expect(listing.image_share_url).to include("/representations/")
    expect(shop.share_image_url).to include("/representations/")
    expect(create(:shop).share_image_url).to be_nil
  end
end
