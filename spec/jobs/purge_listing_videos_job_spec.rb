require "rails_helper"

RSpec.describe PurgeListingVideosJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  it "deletes the video and poster 30 days after a sale and keeps the listing and its photos" do
    listing = create(:listing, :active, :with_image, :with_video)
    keys = [ listing.video.blob.key, listing.video_poster.blob.key ]
    listing.update_columns(status: Listing.statuses[:sold], sold_at: Time.current)

    travel_to(29.days.from_now) { perform_enqueued_jobs { described_class.perform_now } }
    expect(listing.reload.video).to be_attached

    travel_to(31.days.from_now) { perform_enqueued_jobs { described_class.perform_now } }
    listing.reload
    expect(listing.video).not_to be_attached
    expect(listing.video_poster).not_to be_attached
    expect(listing.images).to be_attached
    expect(listing).to be_sold
    keys.each { |key| expect(ActiveStorage::Blob.service.exist?(key)).to be(false) }
  end

  it "keeps the video of a listing relisted inside the window" do
    listing = create(:listing, :active, :with_video, expires_at: Time.current)
    travel_to(10.days.from_now) { listing.renew! }

    travel_to(40.days.from_now) { perform_enqueued_jobs { described_class.perform_now } }
    expect(listing.reload.video).to be_attached
  end
end
