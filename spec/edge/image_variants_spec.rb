require "rails_helper"

# Owner, 2026-10-09 ("Cloudinary without paying for it"): lists show LIGHT
# photos, the gallery a medium one, zoom the original. Production: 75 image
# blobs, avg 947 KB, max 8.9 MB, all served as originals except one 600px
# thumbnail. ADDITIVE only: image_urls / avatar_url / logo_url / cover_url keep
# serving originals for the store apps; the new *_thumb / *_medium fields are
# lazy representation URLs (stable, no N+1), WebP.
#
# The host has no libvips: the "processing" group runs in the API image
# (Dockerfile installs libvips) and skips loudly elsewhere.
RSpec.describe "Light image variants (thumb / medium)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def self.vips?
    require "vips"
    true
  rescue LoadError
    false
  end

  def small_jpeg = { io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "a.jpg", content_type: "image/jpeg" }

  # As if ActiveStorage::AnalyzeJob had run (it is only enqueued in tests).
  def analyzed!(attachments)
    Array(attachments).each { |a| a.blob.update!(metadata: a.blob.metadata.merge("width" => 48, "height" => 48, "analyzed" => true)) }
  end

  def row(path, headers = {})
    get path, headers: headers
    JSON.parse(response.body)
  end

  let(:seller) { create(:user) }
  let(:listing) do
    create(:listing, :active, user: seller).tap do |l|
      l.images.attach(**small_jpeg)
      analyzed!(l.images.attachments)
    end
  end

  describe "fields (additive)" do
    it "the feed lists thumb and medium URLs beside the originals, one per photo" do
      listing
      l = row("/api/v1/listings")["listings"].find { |x| x["id"] == listing.id }
      expect(l["image_thumb_urls"].size).to eq(l["image_urls"].size)
      expect(l["image_medium_urls"].size).to eq(l["image_urls"].size)
      expect(l["image_thumb_urls"].first).to include("/representations/redirect/")
      expect(l["image_urls"].first).to include("/blobs/redirect/") # originals untouched
    end

    it "variant URLs are stable across responses (the apps cache them by URL)" do
      listing
      first = row("/api/v1/listings/#{listing.id}")["listing"].values_at("image_thumb_urls", "image_medium_urls")
      expect(first.flatten).to all(be_present)
      travel 61.seconds
      expect(row("/api/v1/listings/#{listing.id}")["listing"].values_at("image_thumb_urls", "image_medium_urls")).to eq(first)
    end

    it "an avatar has a thumb; a shop has a logo thumb and a medium cover" do
      seller.avatar.attach(**small_jpeg)
      analyzed!(seller.avatar.attachment)
      me = row("/api/v1/users/me", auth_headers_for(seller))["user"]
      expect(me["avatar_thumb_url"]).to include("/representations/redirect/")
      expect(me["avatar_url"]).to include("/blobs/redirect/")

      shop = create(:shop, owner: seller)
      shop.logo.attach(**small_jpeg)
      shop.cover.attach(**small_jpeg)
      analyzed!([ shop.logo.attachment, shop.cover.attachment ])
      s = row("/api/v1/shops/#{shop.id}", auth_headers_for(create(:user)))["shop"]
      expect(s["logo_thumb_url"]).to include("/representations/redirect/")
      expect(s["cover_medium_url"]).to include("/representations/redirect/")
      expect(s.values_at("logo_url", "cover_url")).to all(include("/blobs/redirect/"))
    end

    it "nothing attached → [] / null, never an error" do
      l = create(:listing, :active, user: seller)
      expect(row("/api/v1/listings/#{l.id}")["listing"]["image_thumb_urls"]).to eq([])
      expect(row("/api/v1/users/me", auth_headers_for(seller))["user"]["avatar_thumb_url"]).to be_nil
    end

    it "a blob a variant could fail on falls back to the ORIGINAL, never null or a 500" do
      l = create(:listing, :active, user: seller)
      l.images.attach(**small_jpeg) # not analysed: no width (corrupt, or analysis pending)
      l.images.attach(io: StringIO.new("%PDF-1.4"), filename: "doc.pdf", content_type: "application/pdf") # not variable
      body = row("/api/v1/listings/#{l.id}")["listing"]
      expect(body["image_thumb_urls"]).to eq(body["images"])
      expect(body["image_medium_urls"]).to eq(body["images"])
    end
  end

  describe "processing (libvips)" do
    before { skip "needs libvips — run in the API image (the Dockerfile installs it)" unless self.class.vips? }

    def jpeg(width, height, name = "photo.jpg")
      path = Rails.root.join("tmp/variant_spec_#{SecureRandom.hex(4)}_#{name}")
      bands = 3.times.map { Vips::Image.gaussnoise(width, height, mean: 128, sigma: 40).cast(:uchar) }
      bands.first.bandjoin(bands.drop(1)).write_to_file(path.to_s, **(name.end_with?(".jpg") ? { Q: 90 } : {}))
      path
    end

    def attach_real(record, name, path, content_type)
      record.public_send(name).attach(io: File.open(path), filename: File.basename(path), content_type: content_type)
      Array(record.public_send(name).attachments).each { |a| a.blob.analyze } if record.public_send(name).respond_to?(:attachments)
      record.public_send(name).blob.analyze unless record.public_send(name).respond_to?(:attachments)
    end

    # Follow the representation redirect to the bytes, like an app would.
    def fetch(url)
      get URI(url).path
      follow_redirect! while response.redirect?
      expect(response).to have_http_status(:ok)
      response.body
    end

    def variants_of(path, content_type)
      l = create(:listing, :active, user: seller)
      attach_real(l, :images, path, content_type)
      body = row("/api/v1/listings/#{l.id}")["listing"]
      {
        original: fetch(body["images"].first),
        thumb: fetch(body["image_thumb_urls"].first),
        medium: fetch(body["image_medium_urls"].first)
      }
    end

    def dims(bytes) = Vips::Image.new_from_buffer(bytes, "").then { |i| [ i.width, i.height ] }

    it "a 3000×2000 photo: thumb short side 640, medium ≤ 1440, WebP, aspect kept, far lighter" do
      v = variants_of(jpeg(3000, 2000), "image/jpeg")
      expect(dims(v[:thumb])).to eq([ 960, 640 ])
      expect(dims(v[:medium])).to eq([ 1440, 960 ])
      expect(Vips::Image.new_from_buffer(v[:thumb], "").get("vips-loader")).to start_with("webp")
      expect(v[:thumb].bytesize).to be < v[:original].bytesize / 10
      puts "\n  sample 3000x2000 JPEG: original #{v[:original].bytesize / 1024} KB, medium #{v[:medium].bytesize / 1024} KB, thumb #{v[:thumb].bytesize / 1024} KB"
    end

    it "a tiny original (200×150) is NEVER upscaled" do
      v = variants_of(jpeg(200, 150), "image/jpeg")
      expect(dims(v[:thumb])).to eq([ 200, 150 ])
      expect(dims(v[:medium])).to eq([ 200, 150 ])
    end

    it "portrait and panorama keep their aspect ratio (no crop); a portrait card stays sharp (≥ 540 px wide)" do
      expect(dims(variants_of(jpeg(1500, 4000), "image/jpeg")[:thumb])).to eq([ 600, 1600 ])
      expect(dims(variants_of(jpeg(6000, 1000), "image/jpeg")[:thumb])).to eq([ 1600, 267 ])
      expect(dims(variants_of(jpeg(6000, 1000), "image/jpeg")[:medium])).to eq([ 1440, 240 ])
    end

    it "a PNG with transparency keeps its alpha channel" do
      path = Rails.root.join("tmp/variant_spec_#{SecureRandom.hex(4)}.png")
      rgb = 3.times.map { Vips::Image.gaussnoise(800, 800, mean: 128, sigma: 40).cast(:uchar) }
      alpha = (Vips::Image.black(800, 800) + 0).cast(:uchar)
      rgb.first.bandjoin(rgb.drop(1) + [ alpha ]).pngsave(path.to_s)
      thumb = Vips::Image.new_from_buffer(variants_of(path, "image/png")[:thumb], "")
      expect(thumb.bands).to eq(4)
      expect([ thumb.width, thumb.height ]).to eq([ 640, 640 ])
    end

    it "a HEIC photo gets a WebP thumb (when this vips can write HEIC to make one)" do
      path = Rails.root.join("tmp/variant_spec_#{SecureRandom.hex(4)}.heic")
      begin
        Vips::Image.new_from_file(jpeg(1600, 1200).to_s).heifsave(path.to_s)
      rescue Vips::Error, NoMethodError => e
        skip "this libvips cannot write HEIC (#{e.class}) — reading is what production needs"
      end
      expect(dims(variants_of(path, "image/heic")[:thumb])).to eq([ 853, 640 ])
    end

    it "a corrupt 'JPEG' falls back to the original URL (analysis finds no width)" do
      l = create(:listing, :active, user: seller)
      l.images.attach(io: StringIO.new("not a jpeg at all"), filename: "bad.jpg", content_type: "image/jpeg")
      l.images.attachments.each { |a| a.blob.analyze }
      body = row("/api/v1/listings/#{l.id}")["listing"]
      expect(body["image_thumb_urls"]).to eq(body["images"])
    end

    it "a 1-photo listing has exactly one thumb and one medium" do
      l = create(:listing, :active, user: seller)
      attach_real(l, :images, jpeg(1000, 1000), "image/jpeg")
      body = row("/api/v1/listings/#{l.id}")["listing"]
      expect([ body["images"], body["image_thumb_urls"], body["image_medium_urls"] ].map(&:size)).to eq([ 1, 1, 1 ])
    end
  end
end
