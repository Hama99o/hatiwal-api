require "rails_helper"

# SHOP-MEDIA (docs/SHOP_MEDIA.md): up to 5 shop photos + 1 video, the VID system.
RSpec.describe Shop, "photos + video" do
  include ActiveJob::TestHelper

  let(:jpg) { -> { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") } }
  let(:mp4) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_video.mp4"), "video/mp4") }
  let(:shop) { create(:shop) }

  before { ActiveStorage::Current.url_options = { host: "http://test.host" } }

  describe "the video (HasVideo, shared with Listing)" do
    it "attaches with its poster and length, and refuses over 60 s like a listing video" do
      expect(shop.attach_video!(file: mp4, poster: jpg.call, duration_s: 12)).to be(true)
      expect(shop.reload).to have_attributes(has_video?: true, video_duration_s: 12)
      expect(shop.video_url).to include("/rails/active_storage/blobs/")

      expect(shop.attach_video!(file: mp4, duration_s: 75)).to be(false)
      expect(shop.errors[:video].join).to include("60 seconds")
    end
  end

  describe "#update_gallery!" do
    it "adds photos in order, up to 5" do
      expect(shop.update_gallery!(keep_ids: [], uploads: [ jpg.call, jpg.call ])).to be(true)
      expect(shop.reload.gallery_photo_entries.size).to eq(2)
      expect(shop.gallery_photo_entries.first.keys).to contain_exactly(:id, :url, :medium_url, :thumb_url)
    end

    it "refuses a sixth photo and changes nothing" do
      shop.update_gallery!(keep_ids: [], uploads: Array.new(5) { jpg.call })
      ids = shop.reload.gallery_photo_entries.pluck(:id)

      expect(shop.update_gallery!(keep_ids: ids, uploads: [ jpg.call ])).to be(false)
      expect(shop.errors[:gallery_photos].join).to match(/more than 5/)
      expect(shop.reload.gallery_photo_entries.pluck(:id)).to eq(ids)
    end

    it "reorders and removes in one save; a removed photo's file goes" do
      shop = create(:shop, :with_gallery)
      front, team = shop.gallery_photo_entries.pluck(:id)
      front_key = shop.ordered_gallery_photos.first.blob.key

      perform_enqueued_jobs { shop.update_gallery!(keep_ids: [ team ], uploads: [ jpg.call ]) }

      entries = shop.reload.gallery_photo_entries
      expect(entries.size).to eq(2)
      expect(entries.first[:id]).to eq(team)
      expect(entries.pluck(:id)).not_to include(front)
      expect(ActiveStorage::Blob.service.exist?(front_key)).to be(false)

      shop.update_gallery!(keep_ids: entries.pluck(:id).reverse, uploads: [])
      expect(shop.reload.gallery_photo_entries.pluck(:id)).to eq(entries.pluck(:id).reverse)
    end

    it "ignores ids that are not this shop's own photos (no borrowing another's blob)" do
      other = create(:shop, :with_gallery)
      foreign = other.gallery_photo_entries.first[:id]

      shop.update_gallery!(keep_ids: [ foreign, "garbage" ], uploads: [])

      expect(shop.reload.gallery_photos).not_to be_attached
      expect(other.reload.gallery_photos.count).to eq(2)
    end

    it "refuses a non-image and leaves the gallery as it was" do
      bad = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/not_an_image.zip"), "image/jpeg")
      expect(shop.update_gallery!(keep_ids: [], uploads: [ bad ])).to be(false)
      expect(shop.reload.gallery_photos).not_to be_attached
    end
  end

  describe ".media_purgeable / #purge_media!" do
    it "takes shops closed 30+ days ago that still hold media, and nothing else" do
      old = create(:shop, :with_video)
      old.update_columns(status: described_class.statuses[:closed], closed_at: 31.days.ago)
      photos_only = create(:shop, :with_gallery)
      photos_only.update_columns(status: described_class.statuses[:closed], closed_at: 40.days.ago)

      recent = create(:shop, :with_video)
      recent.update_columns(status: described_class.statuses[:closed], closed_at: 29.days.ago)
      create(:shop, :with_video) # open
      create(:shop).update_columns(status: described_class.statuses[:closed], closed_at: 60.days.ago) # no media

      expect(described_class.media_purgeable).to contain_exactly(old, photos_only)
    end

    it "a shop reopened inside the window drops out" do
      shop = create(:shop, :with_video)
      shop.update_columns(status: described_class.statuses[:closed], closed_at: 31.days.ago)
      shop.update_columns(status: described_class.statuses[:active], closed_at: nil)
      expect(described_class.media_purgeable).to be_empty
    end

    it "purge_media! deletes the video, the poster and every photo" do
      shop = create(:shop, :with_video, :with_gallery)
      perform_enqueued_jobs { shop.purge_media! }
      shop.reload
      expect(shop.video).not_to be_attached
      expect(shop.video_poster).not_to be_attached
      expect(shop.gallery_photos).not_to be_attached
    end
  end
end
