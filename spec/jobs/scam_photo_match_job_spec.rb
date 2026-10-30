require "rails_helper"

# IDEA-5 (1.2.1): matching runs in its own job, after a photo is indexed and when a listing goes
# live (a draft's photos are indexed before it is published; only live listings are matched).
RSpec.describe ScamPhotoMatchJob, :image_search, type: :job do
  include ActiveJob::TestHelper

  it "runs the matcher for the listing" do
    listing = create(:listing, :active)
    allow(ScamPhoto::Matcher).to receive(:call)

    described_class.perform_now(listing.id)

    expect(ScamPhoto::Matcher).to have_received(:call).with(listing)
  end

  it "does nothing for a deleted listing" do
    allow(ScamPhoto::Matcher).to receive(:call)

    described_class.perform_now(0)

    expect(ScamPhoto::Matcher).not_to have_received(:call)
  end

  it "is queued when a draft is published, not on other edits" do
    listing = create(:listing, :with_image)

    expect { listing.update!(status: :active) }.to have_enqueued_job(described_class).with(listing.id)
    expect { listing.update!(title: "New title") }.not_to have_enqueued_job(described_class)
  end

  it "is not queued when search by image is off (no vectors to match)" do
    listing = create(:listing, :with_image)
    Rails.configuration.x.image_search_enabled = false

    expect { listing.update!(status: :active) }.not_to have_enqueued_job(described_class)
  end
end
