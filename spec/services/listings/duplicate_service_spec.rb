require "rails_helper"

# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5):
# Duplicate copies the photos.
RSpec.describe Listings::DuplicateService do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:staff) { create(:user) }
  let(:shop)  { create(:shop, owner: owner) }
  let(:other) { create(:shop, owner: owner) }

  before { shop.shop_members.create!(user: staff, role: :staff) }

  def duplicate(listing, actor, shop_id) = described_class.new(listing: listing, actor: actor, shop_id: shop_id).call

  def add_photo(listing, name)
    listing.images.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open, filename: name, content_type: "image/jpeg")
  end

  it "makes a DRAFT with the text, price, place and copies of the photos, in order" do
    original = create(:listing, :active, user: owner, title: "Bike", price: 4000, expires_at: 10.days.from_now)
    add_photo(original, "front.jpg")
    add_photo(original, "side.jpg")

    copy = duplicate(original, owner, nil)

    expect(copy).to be_draft
    expect(copy.slice(:title, :price, :category_id, :latitude, :shop_id)).to eq(original.slice(:title, :price, :category_id, :latitude, :shop_id))
    expect(copy.expires_at).to be_nil
    expect(copy.images.map { |i| i.filename.to_s }).to eq(%w[front.jpg side.jpg])
    # COPIES: new blobs with the same bytes, never the original's blobs.
    expect(copy.images.map(&:blob_id) & original.images.map(&:blob_id)).to be_empty
    expect(copy.images.map { |i| i.blob.checksum }).to eq(original.images.map { |i| i.blob.checksum })
  end

  # Owner bug, 2026-10-08: a blob whose file is missing failed the whole copy.
  it "skips a photo whose file is missing, logs it, and still copies the rest" do
    original = create(:listing, :active, user: owner)
    add_photo(original, "front.jpg")
    add_photo(original, "lost.jpg")
    add_photo(original, "back.jpg")
    lost = original.images.find { |i| i.filename.to_s == "lost.jpg" }.blob
    lost.service.delete(lost.key)
    allow(Rails.logger).to receive(:warn)

    copy = duplicate(original, owner, nil)

    expect(copy).to be_persisted.and be_draft
    expect(copy.images.map { |i| i.filename.to_s }).to eq(%w[front.jpg back.jpg])
    expect(Rails.logger).to have_received(:warn).with(/blob #{lost.id} has no file/)
  end

  it "deleting the original never removes the duplicate's photos" do
    original = create(:listing, :active, user: owner)
    add_photo(original, "front.jpg")
    copy = duplicate(original, owner, nil)
    blob = copy.images.first.blob

    perform_enqueued_jobs { original.destroy! }

    expect(Listing.exists?(original.id)).to be(false)
    expect(copy.reload.images.count).to eq(1)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    expect(blob.service.exist?(blob.key)).to be(true)
  end

  it "into another shop the caller is on; the caller is the poster" do
    original = create(:listing, :active, user: owner, shop: shop)
    copy = duplicate(original, owner, other.id)
    expect(copy.shop).to eq(other)
    expect(copy.user).to eq(owner)
  end

  it "a staff member duplicates a shop product within the shop, not into their own listings" do
    original = create(:listing, :active, user: owner, shop: shop)
    expect(duplicate(original, staff, shop.id).shop).to eq(shop)
    expect { duplicate(original, staff, nil) }.to raise_error(described_class::Error) { |e| expect(e.code).to eq(:duplicate_forbidden) }
  end

  it "refuses a shop the caller is not on, or a closed one" do
    original = create(:listing, :active, user: owner)
    expect { duplicate(original, owner, create(:shop).id) }
      .to raise_error(described_class::Error) { |e| expect(e.code).to eq(:move_not_member) }
    other.update_columns(status: Shop.statuses[:suspended])
    expect { duplicate(original, owner, other.id) }
      .to raise_error(described_class::Error) { |e| expect(e.code).to eq(:shop_unavailable) }
  end
end
