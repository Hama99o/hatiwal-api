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

  # Hama9900, 2026-10-09: extend to PUBLIC images only.
  describe "public images: avatars, shop logos and covers" do
    def img = { io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "a.jpg", content_type: "image/jpeg" }

    it "an avatar keeps its URL across responses" do
      seller.avatar.attach(**img)
      urls = 2.times.map do |i|
        travel 61.seconds if i.positive?
        get "/api/v1/users/me", headers: auth_headers_for(seller)
        JSON.parse(response.body).dig("user", "avatar_url")
      end
      expect(urls.first).to be_present
      expect(urls.uniq.size).to eq(1)
    end

    it "a shop's logo and cover keep their URLs across responses" do
      shop = create(:shop, owner: seller)
      shop.logo.attach(**img)
      shop.cover.attach(**img)
      bodies = 2.times.map do |i|
        travel 61.seconds if i.positive?
        get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(create(:user))
        JSON.parse(response.body)["shop"].slice("logo_url", "cover_url")
      end
      expect(bodies.first.values).to all(be_present)
      expect(bodies.uniq.size).to eq(1)
    end
  end

  # PRIVATE files never get a permanent link: anyone holding it could open the
  # file forever.
  describe "private files stay private" do
    it "a chat attachment keeps an EXPIRING URL (a new one per response)" do
      buyer = create(:user)
      chat = create(:conversation, listing: listing, buyer: buyer)
      msg = chat.messages.create!(user: buyer, kind: :image_message, body: "photo")
      msg.attachment.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "p.jpg", content_type: "image/jpeg")
      urls = 2.times.map do |i|
        travel 61.seconds if i.positive?
        get "/api/v1/conversations/#{chat.id}/messages", headers: auth_headers_for(buyer)
        JSON.parse(response.body)["messages"].find { |m| m["id"] == msg.id }["attachment_url"]
      end
      expect(urls.first).to be_present
      expect(urls.first).not_to include("/blobs/redirect/")
      expect(urls.first).not_to eq(urls.last)
    end

    it "a verification photo is refused by the permanent blob route" do
      verification = create(:verification_request)
      # The same permanent route PublicImageUrl builds, for a private blob.
      get Rails.application.routes.url_helpers.rails_blob_path(verification.front, only_path: true)
      expect(response).to have_http_status(:not_found)
    end
  end
end
