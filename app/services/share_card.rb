require "vips"
require "rqrcode"

# IDEA-8 (1.2.1, hatiwal-mobile docs/design/SHARE_AND_QR.md §3.5): the printable QR card of a shop
# or a listing — rickshaw stickers, shop windows, counters (docs/MARKETING_PLAN.md §3). Made here,
# never by a QR service: rqrcode encodes, ruby-vips draws (Pango shapes Pashto / Dari with the
# fonts in vendor/fonts), so the app, the web and a printer get the same card.
#
#   ┌───────────── lapis band: the Hatiwal mark + the brand in the card's language ─────────────┐
#   │  the shop's name (or the listing's title + price)                                          │
#   │  the QR (error correction H, 4-module quiet zone, the mark in a white square at its centre)│
#   │  "Scan to open in Hatiwal" · hatiwal.com/s/12                                              │
#   └─────────────────────────────────────── gold rule ──────────────────────────────────────────┘
#
# A6 portrait at 300 dpi. The QR is always black on white (cheap printers, old phone cameras).
module ShareCard
  # Bump when the drawing changes: it is part of the HTTP ETag and the cache key.
  VERSION = 2
  WIDTH = 1240
  HEIGHT = 1748
  LEVEL = :h
  QUIET = 4
  # The QR with its quiet zone spans at most this many pixels: ~ 75 % of the width, so a sticker
  # reads from 1–2 m (design review 2026-10-30: the scan distance grows with the module size).
  QR_SPAN = 930
  QR_TOP = 570
  # The centre square (the mark) covers this share of the QR's side, in modules (< 30 % of
  # the codewords that level H can lose: ~ 8 % of the area).
  LOGO_SIDE = 0.28
  BAND = 280
  LAPIS = "#12224F".freeze
  GOLD = "#E8B23A".freeze
  INK = "#0F172A".freeze
  # The short URL is the manual fallback: dark enough to survive a black-and-white photocopy.
  URL_INK = "#334155".freeze
  FONTS = %w[Rubik-Bold.ttf NotoSansArabic-Bold.ttf].freeze
  # Latin first (Rubik: names, prices, the URL), Pashto / Dari from Noto Sans Arabic.
  FONT = "Rubik, Noto Sans Arabic Bold".freeze
  BRAND = { "en" => "Hatiwal", "ps" => "هټیوال", "fa" => "هتیوال" }.freeze
  # The price in the card's language: the locale's digits, and the afghani's own word.
  DIGITS = { "ps" => "۰۱۲۳۴۵۶۷۸۹", "fa" => "۰۱۲۳۴۵۶۷۸۹" }.freeze
  SEPARATOR = { "ps" => "٬", "fa" => "٬" }.freeze
  CURRENCY_WORD = { "ps" => { "AFN" => "افغانۍ" }, "fa" => { "AFN" => "افغانی" } }.freeze
  # A4 at 72 pt/in is 595.28 x 841.89; A6 is a quarter of it.
  PDF_MEDIA_BOX = "0 0 297.64 419.53".freeze

  module_function

  def png(record, lang:)
    draw(record, card_lang(lang)).write_to_buffer(".png[compression=6]")
  end

  # One page, A6, holding the card as a JPEG — the text is already shaped in the image, so no PDF
  # font handling (and no Arabic shaping) is needed.
  def pdf(record, lang:)
    pdf_wrap(draw(record, card_lang(lang)).write_to_buffer(".jpg[Q=92,strip]"))
  end

  def card_lang(lang) = ShareLink.lang(lang) || "en"

  def url(record, lang) = ShareLink.for(record, lang: card_lang(lang), src: "qr")

  def texts(record, lang)
    lang = card_lang(lang)
    listing = record.is_a?(Listing)
    {
      brand: BRAND.fetch(lang),
      name: listing ? record.title : record.name,
      price: listing && record.price.to_d.positive? ? price_text(record.price.to_i, record.currency, lang) : nil,
      scan: I18n.t("share_card.scan", locale: lang),
      url: url(record, lang).to_s.sub(%r{\Ahttps?://}, "").sub(/\?.*\z/, "")
    }
  end

  # "520,000 AFN" (en), "۵۲۰٬۰۰۰ افغانۍ" (ps), "۵۲۰٬۰۰۰ افغانی" (fa); other currencies keep their code.
  def price_text(amount, currency, lang)
    number = ActiveSupport::NumberHelper.number_to_delimited(amount, delimiter: SEPARATOR.fetch(lang, ","))
    number = number.tr("0123456789", DIGITS[lang]) if DIGITS[lang]
    "#{number} #{CURRENCY_WORD.dig(lang, currency) || currency}"
  end

  # Where the QR's modules are on the card: the top-left of module (0, 0) and the module's size.
  def qr_layout(link)
    count = RQRCode::QRCode.new(link, level: LEVEL).modules.size
    size = QR_SPAN / (count + (2 * QUIET))
    origin_x = ((WIDTH - (size * (count + (2 * QUIET)))) / 2) + (QUIET * size)
    { x: origin_x, y: QR_TOP + (QUIET * size), module: size, count: count }
  end

  # Modules hidden by the mark at the QR's centre.
  def under_logo?(x, y, count)
    side = logo_modules(count)
    first = (count - side) / 2
    x.between?(first, first + side - 1) && y.between?(first, first + side - 1)
  end

  def logo_modules(count)
    side = (count * LOGO_SIDE).floor
    side.even? == count.even? ? side : side - 1 # centred on whole modules
  end

  def logo_share(count) = (logo_modules(count)**2).fdiv(count**2)

  # A line of text as an RGBA image (Pango markup; the fonts come from vendor/fonts).
  def text_image(text, size:, color: INK, width: WIDTH - 160)
    load_fonts
    markup = %(<span foreground="#{color}">#{ERB::Util.html_escape(text)}</span>)
    Vips::Image.text(markup, font: "#{FONT} #{size}", width: width, align: :centre, rgba: true, wrap: :word_char)
  end

  # `text` on at most `lines` lines: whole words dropped from the end, then "…" — never a line cut
  # through its glyphs.
  def fitted_text(text, size:, lines:, color: INK)
    max_height = text_image("Ag", size: size).height * lines * 1.15
    image = text_image(text, size: size, color: color)
    words = text.split
    while image.height > max_height && words.size > 1
      words.pop
      image = text_image("#{words.join(' ')}…", size: size, color: color)
    end
    image
  end

  def draw(record, lang)
    link = url(record, lang) or raise ArgumentError, "PUBLIC_SHARE_BASE_URL is not set"
    words = texts(record, lang)
    card = Vips::Image.black(WIDTH, HEIGHT, bands: 3).new_from_image([ 255, 255, 255 ]).cast(:uchar)
    card = card.draw_rect(rgb(LAPIS), 0, 0, WIDTH, BAND, fill: true)
    card = card.draw_rect(rgb(GOLD), 0, HEIGHT - 28, WIDTH, 28, fill: true)

    card = paste(card, mark(124), (WIDTH - 124) / 2, 28)
    card = paste_centred(card, text_image(words[:brand], size: 58, color: "#FFFFFF"), 168)
    name = fitted_text(words[:name], size: 56, lines: 2)
    # The price is the second hero (a listing); a shop's name alone sits lower, half-way to the QR.
    name_top = words[:price] ? BAND + 22 : BAND + 70
    card = paste_centred(card, name, name_top)
    card = paste_centred(card, text_image(words[:price], size: 88, color: LAPIS), name_top + name.height + 4) if words[:price]

    layout = qr_layout(link)
    card = card.insert(qr_image(link, layout[:module]), layout[:x] - (QUIET * layout[:module]), layout[:y] - (QUIET * layout[:module]))
    card = logo_in_qr(card, layout)

    below = layout[:y] + ((layout[:count] + QUIET) * layout[:module]) + 10
    card = paste_centred(card, text_image(words[:scan], size: 46), below)
    paste_centred(card, text_image(words[:url], size: 44, color: URL_INK), below + 80)
  end

  def qr_image(link, size)
    modules = RQRCode::QRCode.new(link, level: LEVEL).modules
    pixels = modules.map { |row| row.map { |dark| dark ? 0 : 255 }.pack("C*") }.join
    qr = Vips::Image.new_from_memory(pixels, modules.size, modules.size, 1, :uchar).zoom(size, size)
    qr = qr.embed(QUIET * size, QUIET * size, qr.width + (2 * QUIET * size), qr.height + (2 * QUIET * size), background: [ 255 ])
    qr.bandjoin([ qr, qr ]).copy(interpretation: :srgb)
  end

  def logo_in_qr(card, layout)
    side = logo_modules(layout[:count])
    first = (layout[:count] - side) / 2
    x = layout[:x] + (first * layout[:module])
    y = layout[:y] + (first * layout[:module])
    pixels = side * layout[:module]
    card = card.draw_rect([ 255, 255, 255 ], x, y, pixels, pixels, fill: true)
    inner = pixels - (2 * layout[:module])
    paste(card, mark(inner), x + layout[:module], y + layout[:module])
  end

  # The Hatiwal mark (vendor/brand/hatiwal-mark-512.png: the same file as hatiwal-web's
  # public/icon-512.png). A PNG, not public/icon.svg: libvips blocks its SVG loader (untrusted).
  def mark(size)
    @mark ||= Vips::Image.new_from_file(Rails.root.join("vendor/brand/hatiwal-mark-512.png").to_s)
    image = @mark.thumbnail_image(size, height: size)
    image = image.extract_band(0, n: 3) if image.bands > 3
    image.bandjoin(rounded_mask(size, (size * 0.18).round)) # the app icon's corner radius (rx 18 of 100)
  end

  def rounded_mask(size, radius)
    mask = Vips::Image.black(size, size).cast(:uchar)
    mask = mask.draw_rect(255, radius, 0, size - (2 * radius), size, fill: true)
    mask = mask.draw_rect(255, 0, radius, size, size - (2 * radius), fill: true)
    [ [ radius, radius ], [ size - radius - 1, radius ], [ radius, size - radius - 1 ], [ size - radius - 1, size - radius - 1 ] ]
      .reduce(mask) { |m, (cx, cy)| m.draw_circle(255, cx, cy, radius, fill: true) }
  end

  def paste(card, overlay, x, y)
    card.composite2(overlay, :over, x: x, y: y).extract_band(0, n: 3).cast(:uchar)
  end

  def paste_centred(card, overlay, y) = paste(card, overlay, (WIDTH - overlay.width) / 2, y)

  def rgb(hex) = hex.delete("#").scan(/../).map { |c| c.to_i(16) }

  def load_fonts
    @load_fonts ||= FONTS.each { |file| Vips::Image.text(".", fontfile: Rails.root.join("vendor/fonts", file).to_s) }
  end

  def pdf_wrap(jpeg)
    content = "q 297.64 0 0 419.53 0 0 cm /Im0 Do Q"
    image = "<< /Type /XObject /Subtype /Image /Width #{WIDTH} /Height #{HEIGHT} /ColorSpace /DeviceRGB " \
            "/BitsPerComponent 8 /Filter /DCTDecode /Length #{jpeg.bytesize} >>\nstream\n"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>".b,
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".b,
      "<< /Type /Page /Parent 2 0 R /MediaBox [#{PDF_MEDIA_BOX}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>".b,
      image.b + jpeg.b + "\nendstream".b,
      "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream".b
    ]
    out = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
    offsets = objects.each_with_index.map do |body, i|
      offset = out.bytesize
      out << "#{i + 1} 0 obj\n".b << body << "\nendobj\n".b
      offset
    end
    xref = out.bytesize
    out << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n".b
    offsets.each { |o| out << format("%010d 00000 n \n", o).b }
    out << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
  end
end
