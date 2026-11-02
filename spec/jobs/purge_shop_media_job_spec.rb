require "rails_helper"

RSpec.describe PurgeShopMediaJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  it "deletes a closed shop's photos + video 30 days after it closed, keeping the shop row" do
    shop = create(:shop, :with_video, :with_gallery)
    shop.close!

    travel_to(29.days.from_now) { perform_enqueued_jobs { described_class.perform_now } }
    expect(shop.reload.video).to be_attached

    travel_to(31.days.from_now) { perform_enqueued_jobs { described_class.perform_now } }
    shop.reload
    expect(shop).to be_closed
    expect(shop.video).not_to be_attached
    expect(shop.gallery_photos).not_to be_attached
  end

  it "never touches an open shop's media" do
    shop = create(:shop, :with_video, :with_gallery)
    travel_to(400.days.from_now) { perform_enqueued_jobs { described_class.perform_now } }
    expect(shop.reload.video).to be_attached
    expect(shop.gallery_photos.count).to eq(2)
  end
end
