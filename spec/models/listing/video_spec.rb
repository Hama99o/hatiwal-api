require "rails_helper"

# VID (1.1.9, docs/LISTING_VIDEO.md).
RSpec.describe Listing, "video" do
  include ActiveJob::TestHelper

  before { ActiveStorage::Current.url_options = { host: "http://test.host" } }
  let(:mp4) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_video.mp4"), "video/mp4") }
  let(:jpg) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }

  describe "#attach_video!" do
    let(:listing) { create(:listing, :active, :with_image) }

    it "attaches the video, its poster and the client's duration" do
      expect(listing.attach_video!(file: mp4, poster: jpg, duration_s: "29.6")).to be(true)
      expect(listing.reload).to have_attributes(has_video?: true, video_duration_s: 30)
      expect(listing.video_url).to include("/rails/active_storage/blobs/")
      expect(listing.video_poster_url).to be_present
    end

    it "refuses a non-video and leaves no blob behind" do
      expect(listing.attach_video!(file: jpg)).to be(false)
      expect(listing.errors[:video].join).to match(/unsupported file type/)
      perform_enqueued_jobs
      expect(listing.reload.video).not_to be_attached
      expect(ActiveStorage::Blob.where(filename: "test_image.jpg").count).to eq(1) # the photo only
    end

    it "refuses a zero or over-60 s duration" do
      expect(listing.attach_video!(file: mp4, duration_s: 0)).to be(false)
      expect(listing.attach_video!(file: mp4, duration_s: 75)).to be(false)
      expect(listing.errors[:video].join).to include("60 seconds")
    end

    it "is fine without a duration (old web upload, the analyzer may fill it)" do
      expect(listing.attach_video!(file: mp4)).to be(true)
      expect(listing.reload.video).to be_attached
    end
  end

  describe "without a video" do
    subject(:listing) { build(:listing) }

    it { is_expected.to have_attributes(has_video?: false, video_url: nil, video_poster_url: nil, video_duration_s: nil) }
  end

  describe "#off_market_since" do
    it "is the deletion, sale or expiry time, and nil while live or a draft" do
      expect(build(:listing, :active).off_market_since).to be_nil
      expect(build(:listing, :draft).off_market_since).to be_nil
      expect(build(:listing, :sold, sold_at: 3.days.ago.round).off_market_since).to eq(3.days.ago.round)
      expect(build(:listing, :expired, expires_at: 2.days.ago.round).off_market_since).to eq(2.days.ago.round)
      expect(build(:listing, :active, removed_at: 1.day.ago.round).off_market_since).to eq(1.day.ago.round)
    end
  end

  describe ".video_purgeable" do
    def with_video(*traits, **attrs)
      create(:listing, *traits, :with_video).tap { |l| l.update_columns(attrs) if attrs.any? }
    end

    it "takes videos of listings sold, expired or deleted 30+ days ago, and nothing else" do
      sold_old    = with_video(:sold, sold_at: 31.days.ago)
      expired_old = with_video(:active, expires_at: 31.days.ago)
      held_old    = with_video(:reserved, expires_at: 40.days.ago)
      deleted_old = with_video(:active, removed_at: 31.days.ago)

      with_video(:sold, sold_at: 29.days.ago)
      with_video(:active, expires_at: 29.days.ago)
      with_video(:active, removed_at: 29.days.ago)
      with_video(:active)
      with_video(:draft)
      create(:listing, :sold).update_columns(sold_at: 60.days.ago) # no video

      expect(described_class.video_purgeable).to contain_exactly(sold_old, expired_old, held_old, deleted_old)
    end

    it "lets the window be cancelled by coming back to live (undo of sold, renew, restore)" do
      sold = with_video(:sold, sold_at: 31.days.ago)
      sold.update_columns(status: described_class.statuses[:active], sold_at: nil, expires_at: 60.days.from_now)
      expired = with_video(:active, expires_at: 31.days.ago)
      expired.renew!
      deleted = with_video(:active, removed_at: 31.days.ago)
      deleted.restore!

      expect(described_class.video_purgeable).to be_empty
    end
  end
end
