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

  describe "the video (VID, owner 2026-10-19)" do
    let(:mp4) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_video.mp4"), "video/mp4") }

    def file_of(attachment) = ActiveStorage::Blob.service.exist?(attachment.blob.key)

    it "copies the video, its poster and its length as NEW files" do
      original = create(:listing, :active, :with_image, :with_video, user: owner)

      copy = duplicate(original, owner, nil).reload

      expect(copy.video).to be_attached
      expect(copy.video_poster).to be_attached
      expect(copy.video_duration_s).to eq(2)
      expect(copy.video.blob_id).not_to eq(original.video.blob_id)
      expect(copy.video_poster.blob_id).not_to eq(original.video_poster.blob_id)
      expect(copy.video.blob.checksum).to eq(original.video.blob.checksum)
    end

    it "copies a sold listing's video while it still exists" do
      original = create(:listing, :sold, :with_image, :with_video, user: owner)
      expect(duplicate(original, owner, nil).reload.video).to be_attached
    end

    it "the original's 30-day purge never touches the duplicate's video, and the reverse" do
      original = create(:listing, :active, :with_image, :with_video, user: owner)
      copy = duplicate(original, owner, nil).reload
      original.update_columns(status: Listing.statuses[:sold], sold_at: 31.days.ago)

      perform_enqueued_jobs { PurgeListingVideosJob.perform_now }

      expect(original.reload.video).not_to be_attached
      copy.reload
      expect(copy.video).to be_attached
      expect(file_of(copy.video)).to be(true)
      expect(file_of(copy.video_poster)).to be(true)
    end

    it "removing or replacing the duplicate's video leaves the original's file" do
      original = create(:listing, :active, :with_image, :with_video, user: owner)
      copy = duplicate(original, owner, nil).reload

      perform_enqueued_jobs { copy.attach_video!(file: mp4, duration_s: 2) }
      perform_enqueued_jobs { copy.reload.purge_video! }

      original.reload
      expect(original.video).to be_attached
      expect(file_of(original.video)).to be(true)
      expect(file_of(original.video_poster)).to be(true)
    end

    it "skips a video whose file is missing; the draft and photos still come through" do
      original = create(:listing, :active, :with_image, :with_video, user: owner)
      ActiveStorage::Blob.service.delete(original.video.blob.key)

      copy = duplicate(original, owner, nil).reload

      expect(copy.images).to be_attached
      expect(copy.video).not_to be_attached
      expect(copy.video_poster).not_to be_attached
    end
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

  # Review 2026-10-08 (HIGH): staff on two shops copied one shop's goods into the other.
  it "refuses staff copying someone else's shop product into a second shop they are on" do
    other.shop_members.create!(user: staff, role: :staff)
    original = create(:listing, :active, user: owner, shop: shop)
    expect { duplicate(original, staff, other.id) }
      .to raise_error(described_class::Error) { |e| expect(e.code).to eq(:duplicate_forbidden) }
  end

  it "the poster (still a member) or a manager may copy it out of the shop" do
    other.shop_members.create!(user: staff, role: :staff)
    own = create(:listing, :active, user: staff, shop: shop)
    expect(duplicate(own, staff, other.id).shop).to eq(other)
    expect(duplicate(own, staff, nil).shop).to be_nil

    manager = create(:user)
    shop.shop_members.create!(user: manager, role: :manager)
    theirs = create(:listing, :active, user: owner, shop: shop)
    expect(duplicate(theirs, manager, nil).user).to eq(manager)
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
