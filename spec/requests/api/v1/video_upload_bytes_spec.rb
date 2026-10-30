require "rails_helper"

# Security (2026-10-30): a video upload is typed by its BYTES, not its name. Active Storage's identify falls back
# to the file name, so a text file sent as "video.mp4" became video/mp4 and passed the type validation. The
# sniff (Marcel, bytes only) over the seed clip and phone-style recordings — iPhone .mov H.264/HEVC, Android .mp4
# H.264/HEVC, .3gp, fragmented mp4 — types every genuine clip; text and random bytes are octet-stream
# (hatiwal-mobile docs/qa-1.2.1/datasaver/security/sniff-results.txt).
RSpec.describe "Video uploads are typed by their bytes", type: :request do
  let(:seller) { create(:user) }
  let(:headers) { auth_headers_for(seller) }
  let(:listing) { create(:listing, :active, :with_image, user: seller) }
  let(:shop) { create(:shop, owner: seller) }

  def fixture(name, type) = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), type)

  def text_as_mp4
    file = Tempfile.new([ "video", ".mp4" ])
    file.write("this is not a video\n" * 100)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "video/mp4", original_filename: "video.mp4")
  end

  it "a text file named video.mp4 (sent as video/mp4) is refused on the listing's one-shot upload" do
    put "/api/v1/my/listings/#{listing.id}/video", params: { video: text_as_mp4, duration_s: 2 }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(listing.reload.video).not_to be_attached
  end

  it "and on the shop's" do
    put "/api/v1/shops/#{shop.id}/video", params: { video: text_as_mp4, duration_s: 2 }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(shop.reload.video).not_to be_attached
  end

  { "an mp4" => [ "test_video.mp4", "video/mp4" ], "an iPhone HEVC .mov" => [ "test_video_iphone_hevc.mov", "video/quicktime" ] }.each do |what, (name, type)|
    it "#{what} is accepted, stored with the type its bytes say" do
      put "/api/v1/my/listings/#{listing.id}/video", params: { video: fixture(name, "application/octet-stream"), duration_s: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(listing.reload.video.blob.content_type).to eq(type)
    end
  end
end
