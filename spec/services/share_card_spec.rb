require "rails_helper"

# IDEA-8 (1.2.1, hatiwal-mobile docs/design/SHARE_AND_QR.md §3.5): the printable QR card of a
# shop or a listing, made on our server (rqrcode + ruby-vips, no third-party service): A6 portrait
# at 300 dpi, the Hatiwal mark, the name in the card's language, the QR to the share link
# (src=qr), one call to action and the short URL.
RSpec.describe ShareCard do
  let(:shop) { create(:shop, name: "Safi Cosmetics") }
  let(:listing) { create(:listing, :active, :with_image, title: "Toyota Corolla 2010", price: 520_000, currency: "AFN") }

  around do |example|
    previous = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    ENV["PUBLIC_SHARE_BASE_URL"] = "https://hatiwal.com"
    example.run
  ensure
    ENV["PUBLIC_SHARE_BASE_URL"] = previous
  end

  def image(bytes) = Vips::Image.new_from_buffer(bytes, "")

  # Reads the QR back from the PNG: the centre pixel of every module outside the logo square must
  # be dark exactly where the encoding of `url` has a dark module.
  def expect_qr_reads(bytes, url)
    img = image(bytes).colourspace(:b_w).extract_band(0)
    layout = described_class.qr_layout(url)
    modules = RQRCode::QRCode.new(url, level: :h).modules
    checked = 0
    modules.each_with_index do |row, y|
      row.each_with_index do |dark, x|
        next if described_class.under_logo?(x, y, modules.size)

        px = img.getpoint(layout[:x] + (x * layout[:module]) + (layout[:module] / 2), layout[:y] + (y * layout[:module]) + (layout[:module] / 2)).first
        expect(px < 128).to eq(dark), "module (#{x}, #{y}) of #{url}"
        checked += 1
      end
    end
    expect(checked).to be > (modules.size**2) * 0.8
  end

  describe ".png" do
    it "is an A6 card at 300 dpi whose QR reads the shop's share link (src=qr, the card's language)" do
      bytes = described_class.png(shop, lang: "ps")

      expect(bytes.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
      expect([ image(bytes).width, image(bytes).height ]).to eq([ 1240, 1748 ])
      expect_qr_reads(bytes, "https://hatiwal.com/s/#{shop.id}?lang=ps&src=qr")
    end

    it "a listing card reads the listing link" do
      expect_qr_reads(described_class.png(listing, lang: "en"), "https://hatiwal.com/l/#{listing.id}?lang=en&src=qr")
    end

    it "an unknown language falls back to English" do
      expect_qr_reads(described_class.png(shop, lang: "xx"), "https://hatiwal.com/s/#{shop.id}?lang=en&src=qr")
    end

    it "uses error correction H (30 %: the logo in the centre and a scratched sticker)" do
      expect(described_class::LEVEL).to eq(:h)
      expect(described_class.logo_share(RQRCode::QRCode.new("https://hatiwal.com/s/1?lang=en&src=qr", level: :h).modules.size))
        .to be <= 0.12
    end
  end

  describe ".texts" do
    it "spells the brand per language (ps هټیوال with ټ, fa هتیوال) and says what to do" do
      expect(described_class.texts(shop, "ps")).to include(brand: "هټیوال", name: "Safi Cosmetics", url: "hatiwal.com/s/#{shop.id}")
      expect(described_class.texts(shop, "fa")[:brand]).to eq("هتیوال")
      expect(described_class.texts(shop, "en")[:brand]).to eq("Hatiwal")
      %w[en ps fa].each { |l| expect(described_class.texts(shop, l)[:scan]).to eq(I18n.t("share_card.scan", locale: l)) }
    end

    it "a listing card carries the title and the price" do
      expect(described_class.texts(listing, "en")).to include(name: "Toyota Corolla 2010", price: "520,000 AFN")
    end
  end

  describe "Pashto and Dari text (no tofu: the fonts travel with the app, vendor/fonts)" do
    it "draws real, different glyphs for ټ and ښ — not the same missing-glyph box" do
      tofu = described_class.text_image("\u{10FFFD}", size: 60)
      te = described_class.text_image("ټ", size: 60)
      xin = described_class.text_image("ښ", size: 60)

      expect(te.avg).not_to eq(xin.avg)
      expect([ te.width, te.avg ]).not_to eq([ tofu.width, tofu.avg ])
    end
  end

  describe ".pdf" do
    it "is a one-page A6 PDF holding the same card" do
      pdf = described_class.pdf(shop, lang: "fa")

      expect(pdf).to start_with("%PDF-1.4")
      expect(pdf).to include("/MediaBox [0 0 297.64 419.53]", "/Filter /DCTDecode", "/Width 1240", "/Height 1748")
      expect(pdf.rstrip).to end_with("%%EOF")
      image_object = pdf.b.match(%r{/Subtype /Image[^>]*/Length (\d+)[^>]*>>\s*stream\r?\n}m)
      jpeg = pdf.b.byteslice(image_object.end(0), image_object[1].to_i)
      expect([ image(jpeg).width, image(jpeg).height ]).to eq([ 1240, 1748 ])
    end
  end
end
