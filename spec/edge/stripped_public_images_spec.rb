require "rails_helper"

# d0 hunt round 2, 2026-10-11 (supervisor: on the 1.1.6 deploy). The web
# uploads the raw file and, since 1.1.6, image_urls served the ORIGINAL through
# the permanent blob route — with its EXIF, GPS included: a photo taken at home
# and listed from the web published the seller's home coordinates. The 600 px
# thumbnail_url kept metadata too. Every public image is now a STRIPPED
# variant (full size for zoom, same format, alpha kept); only a blob that can't
# be processed falls back to the original.
#
# The host has no libvips: the byte-level group runs in the API image.
RSpec.describe "Public images are served without their metadata (no GPS)", type: :request do
  def self.vips?
    require "vips"
    true
  rescue LoadError
    false
  end

  let(:gps_photo) { Rails.root.join("spec/fixtures/files/gps_photo.jpg") }
  let(:seller) { create(:user) }

  def attach(record, name, path, type = "image/jpeg")
    record.public_send(name).attach(io: File.open(path), filename: File.basename(path), content_type: type)
  end

  def analyzed!(attachments)
    Array(attachments).each { |a| a.blob.update!(metadata: a.blob.metadata.merge("width" => 1200, "height" => 900, "analyzed" => true)) }
  end

  describe "URL shapes (host)" do
    it "image_urls and thumbnail_url are representation URLs for a processable photo, same count" do
      l = create(:listing, :active, user: seller).tap { |x| attach(x, :images, gps_photo) }
      analyzed!(l.images.attachments)
      get "/api/v1/listings/#{l.id}"
      body = JSON.parse(response.body)["listing"]
      expect(body["images"].size).to eq(1)
      expect(body["images"].first).to include("/representations/redirect/")
      expect(body["thumbnail_url"]).to include("/representations/redirect/")
    end

    it "an unprocessable blob still falls back to the original (never null)" do
      l = create(:listing, :active, user: seller).tap { |x| attach(x, :images, gps_photo) } # not analysed
      get "/api/v1/listings/#{l.id}"
      expect(JSON.parse(response.body)["listing"]["images"].first).to include("/blobs/redirect/")
    end
  end

  describe "served bytes (libvips)" do
    before { skip "needs libvips — run in the API image (the Dockerfile installs it)" unless self.class.vips? }

    def fetch(url)
      get URI(url).path
      follow_redirect! while response.redirect?
      expect(response).to have_http_status(:ok)
      response.body
    end

    def gps_fields(bytes) = Vips::Image.new_from_buffer(bytes, "").get_fields.grep(/gps/i)

    it "the fixture really carries GPS (so the checks below mean something)" do
      expect(gps_fields(File.binread(gps_photo))).not_to be_empty
    end

    it "a listing photo: image_urls (zoom, full size) and thumbnail_url carry no GPS; zoom keeps its size" do
      l = create(:listing, :active, user: seller).tap { |x| attach(x, :images, gps_photo) }
      l.images.attachments.each { |a| a.blob.analyze }
      get "/api/v1/listings/#{l.id}"
      body = JSON.parse(response.body)["listing"]
      full = fetch(body["images"].first)
      thumb = fetch(body["thumbnail_url"])
      expect(gps_fields(full)).to be_empty
      expect(gps_fields(thumb)).to be_empty
      img = Vips::Image.new_from_buffer(full, "")
      expect([ img.width, img.height ]).to eq([ 1200, 900 ])
    end

    it "an avatar and a shop logo carry no GPS" do
      attach(seller, :avatar, gps_photo)
      seller.avatar.blob.analyze
      shop = create(:shop, owner: seller)
      attach(shop, :logo, gps_photo)
      shop.logo.blob.analyze
      get "/api/v1/users/me", headers: auth_headers_for(seller)
      expect(gps_fields(fetch(JSON.parse(response.body)["user"]["avatar_url"]))).to be_empty
      get "/api/v1/shops/#{shop.id}", headers: auth_headers_for(create(:user))
      expect(gps_fields(fetch(JSON.parse(response.body)["shop"]["logo_url"]))).to be_empty
    end

    it "a PNG with transparency keeps its alpha in the stripped full-size image" do
      path = Rails.root.join("tmp/strip_spec_#{SecureRandom.hex(4)}.png")
      rgb = 3.times.map { Vips::Image.black(300, 300).cast(:uchar) + 100 }
      rgb.first.bandjoin(rgb.drop(1) + [ Vips::Image.black(300, 300).cast(:uchar) ]).pngsave(path.to_s)
      l = create(:listing, :active, user: seller).tap { |x| attach(x, :images, path, "image/png") }
      l.images.attachments.each { |a| a.blob.analyze }
      get "/api/v1/listings/#{l.id}"
      expect(Vips::Image.new_from_buffer(fetch(JSON.parse(response.body)["listing"]["images"].first), "").bands).to eq(4)
    end
  end
end
