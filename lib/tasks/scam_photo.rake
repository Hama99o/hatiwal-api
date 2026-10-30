# IDEA-5 scam photo detection (1.2.1, hatiwal-mobile docs/design/SCAM_PHOTO.md).
namespace :scam_photo do
  desc "Hash the listing photos embedded before 1.2.1, then match every live listing once (inline)"
  task backfill: :environment do
    abort "scam photo detection is off (SCAM_PHOTO_ENABLED=0, or search by image off)" unless ScamPhoto.enabled?

    started = Time.current
    hashed = failed = 0
    ListingImageEmbedding.current_model.where(photo_hashes: nil).includes(attachment: :blob).find_each do |row|
      hashed += 1 if ImageSearch::Indexer.call(row.attachment)
    rescue ActiveStorage::FileNotFoundError => e
      failed += 1
      Rails.logger.warn("[scam_photo] backfill skipped attachment #{row.attachment_id}: #{e.class}")
    end
    puts "scam_photo:backfill hashed=#{hashed} failed=#{failed}"

    matched = 0
    listings = Listing.live.not_removed.where(id: ListingImageEmbedding.current_model.where.not(photo_hashes: nil).select(:listing_id))
    listings.find_each { |listing| matched += ScamPhoto::Matcher.call(listing).size }
    puts "scam_photo:backfill listings=#{listings.count} matches=#{matched} " \
         "open_flags=#{Flag.open.source_reused_photo.count} in #{(Time.current - started).round(1)} s"
  end
end
