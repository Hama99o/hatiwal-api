require "vips"

module ScamPhoto
  # A transform-invariant perceptual hash of a listing photo (IDEA-5, 1.2.1; hatiwal-mobile
  # docs/design/SCAM_PHOTO.md). CLIP alone cannot tell "the same photo" from "another photo of the
  # same kind of product" (measured: 0.94 vs copies down to 0.57), so a 64-bit DCT pHash is kept
  # alongside it.
  #
  # A photo gets 9 hashes, in this order:
  #   stored (STORED): itself, mirrored, rotated 90/180/270, its centre 80 % crop, that crop mirrored
  #   query  (QUERY):  itself, and itself with uniform borders trimmed (the photo inside a screenshot)
  # The distance of two photos is the smallest Hamming distance of one's stored hashes against the
  # other's query hashes, both ways. Re-saved copies are at 0–12, mirrored / rotated / centre-cropped
  # ones at 0–2; different photos of look-alike products at 8 and more (production + crafted copies,
  # docs/qa-1.2.1/scam-photo/measurement/).
  module Hasher
    class InvalidImage < StandardError; end

    # At most this many differing bits (of 64) is "the same photo" — together with the CLIP
    # pre-filter (Matcher::MIN_COSINE). Measured: recall 0.76 (re-saved 0.99, edited 0.53),
    # 0 false positives in 2149 cross-seller non-copies.
    MATCH_DISTANCE = 10
    STORED = 7
    QUERY = 2
    SIZE = STORED + QUERY
    UINT64 = (2**64) - 1

    # 8 rows of the 32-point DCT-II basis (only the low frequencies are kept).
    BASIS = Array.new(8) { |u| Array.new(32) { |x| Math.cos((2 * x + 1) * u * Math::PI / 64) } }.freeze

    module_function

    # bytes -> 9 Integers, each a signed 64-bit value (fits Postgres bigint).
    def hashes(bytes)
      image = srgb(Vips::Image.new_from_buffer(bytes, "").autorot)
      crop = centre(image)
      stored = [ image, image.fliphor, image.rot90, image.rot180, image.rot270, crop, crop.fliphor ]
      query = [ image, trimmed(image) ]
      (stored + query).map { |i| signed(phash(i)) }
    rescue Vips::Error => e
      raise InvalidImage, e.message.lines.first.to_s.strip
    end

    # The smallest Hamming distance of a's stored hashes against b's query hashes, and back.
    def distance(a, b)
      [ one_way(a, b), one_way(b, a) ].min
    end

    def one_way(from, to)
      from.first(STORED).product(to.last(QUERY)).map { |x, y| ((x ^ y) & UINT64).to_s(2).count("1") }.min
    end

    def phash(image)
      grey = image.colourspace(:b_w).extract_band(0)
      grey = grey.resize(32.0 / grey.width, vscale: 32.0 / grey.height, kernel: :linear)
      pixels = grey.to_a.map { |row| row.map { |px| px.is_a?(Array) ? px[0] : px } }
      rows = pixels.map { |r| BASIS.map { |basis| r.each_index.sum { |x| r[x] * basis[x] } } }       # 32 x 8
      dct = BASIS.map { |basis| (0...8).map { |u| rows.each_index.sum { |y| rows[y][u] * basis[y] } } } # 8 x 8
      flat = dct.flatten
      median = flat.drop(1).sort[(flat.size - 1) / 2]
      flat.each_with_index.reduce(0) { |bits, (c, i)| (bits << 1) | (i.positive? && c > median ? 1 : 0) }
    end

    def srgb(image)
      image = image.colourspace(:srgb) unless image.interpretation == :srgb
      image = image.extract_band(0, n: 3) if image.bands > 3
      image = image.bandjoin([ image, image ]) if image.bands == 1
      image.cast(:uchar)
    end

    def centre(image)
      image.crop((image.width * 0.1).to_i, (image.height * 0.1).to_i, (image.width * 0.8).to_i, (image.height * 0.8).to_i)
    end

    # The photo inside uniform borders (a screenshot: a status bar, then the app's screen): up to 3
    # passes, each trimming the colour found in the top-left corner. Stops when a pass would keep
    # less than a quarter of either side (the photo itself is not a border).
    def trimmed(image)
      3.times.reduce(image) do |img, _|
        background = img.getpoint(0, 0)
        left, top, width, height = img.find_trim(threshold: 25, background: background)
        break img unless width > img.width / 4 && height > img.height / 4 && (width < img.width || height < img.height)

        img.crop(left, top, width, height)
      end
    rescue Vips::Error
      image
    end

    def signed(value) = value >= 2**63 ? value - (2**64) : value
  end
end
