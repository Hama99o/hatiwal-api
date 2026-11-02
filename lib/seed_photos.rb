# Photos for the development / demo seed, from committed CC0 files
# (db/seeds/images, sources in its README) — never the network: loremflickr
# started answering 401 "Bot check", the old seed swallowed the error, and 75 of
# 116 dev listings ended up photo-less (2026-10-09).
#
# A listing gets photos from its TOP-LEVEL category, files whose words match its
# title first ("Toyota Corolla 2015" → car-corolla-*), rotated by id so
# neighbours differ. A listing whose photos are all present and non-empty is left
# alone; one with a missing or empty file is re-attached. A fixture that is
# missing or empty raises: a seed must never leave a 0-byte image behind.
module SeedPhotos
  DIR = Rails.root.join("db/seeds/images")
  CONTENT_TYPE = "image/jpeg".freeze

  class BadFixture < StandardError; end

  module_function

  def files_for(category)
    top = category
    top = top.parent while top&.parent
    return [] unless top

    Dir[DIR.join(top.slug, "*.jpg").to_s].sort
  end

  # Every attached photo has bytes, and its file is really in storage.
  def healthy?(listing)
    listing.images.attached? &&
      listing.images.all? { |a| a.blob.byte_size.to_i.positive? && a.blob.service.exist?(a.blob.key) }
  end

  # :kept (already healthy), :attached, or :no_fixtures (nothing for its category).
  # `hint`: extra words to match (the seed's "motorcycle,motorbike").
  def attach!(listing, hint: nil, count: 3)
    return :kept if healthy?(listing)

    picks = pick(files_for(listing.category), listing, count, hint)
    return :no_fixtures if picks.empty?

    listing.images.purge if listing.images.attached?
    picks.each do |path|
      raise BadFixture, "seed photo missing or empty: #{path}" unless File.file?(path) && File.size(path).positive?

      listing.images.attach(io: File.open(path), filename: File.basename(path), content_type: CONTENT_TYPE)
    end
    raise BadFixture, "listing ##{listing.id}: an attached seed photo has no bytes" unless healthy?(listing.reload)

    :attached
  end

  def pick(files, listing, count, hint = nil)
    return [] if files.empty?

    words = "#{listing.title} #{hint}".downcase.scan(/[a-z]+/)
    matching, others = files.partition { |f| (File.basename(f, ".jpg").split("-") - %w[1 2 3 4 5 6 7 8 9]).intersect?(words) }
    offset = listing.id.to_i
    [ *matching.rotate(offset), *others.rotate(offset) ].first([ count, files.size ].min)
  end
end
