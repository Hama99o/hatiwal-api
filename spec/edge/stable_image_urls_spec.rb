require "rails_helper"

# Owner, 2026-10-09: "on Bazaar the pictures are good, but every time I open My
# shop or My listings all the pictures load again". The apps cache images by
# URL (expo-image memory-disk). Bazaar's cards use `thumbnail_url`, a
# representation URL that never changes; My listings' cards use `image_urls`,
# which were `attachment.url` — a Disk-service URL signed with an expiry, so a
# NEW string on every response (and dead after service_urls_expire_in). Every
# refresh missed the cache and re-downloaded full-size originals.
RSpec.describe "Listing image URLs are stable across responses", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:seller) { create(:user) }
  let!(:listing) { create(:listing, :active, :with_image, user: seller) }

  def my_listing_urls
    get "/api/v1/my/listings", headers: auth_headers_for(seller)
    JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }["image_urls"]
  end

  it "the same image has the same URL a minute later (My listings)" do
    first = my_listing_urls
    travel 61.seconds
    expect(my_listing_urls).to eq(first)
    expect(first).to all(be_present)
  end

  it "the URL still opens the image (a redirect to the file, as the thumbnail does)" do
    url = my_listing_urls.first
    get URI(url).path
    expect(response).to have_http_status(:redirect).or have_http_status(:ok)
  end
end
