# Re-attach seed photos (SeedPhotos, committed CC0 files) to every listing in
# THIS database whose photos are missing, empty, or absent — without reseeding
# anything else. Development / QA only.
#   bin/rails db:seed:repair_photos
namespace :db do
  namespace :seed do
    desc "Re-attach committed seed photos to listings whose photos are missing or empty"
    task repair_photos: :environment do
      abort "refusing: production" if Rails.env.production?

      puts "DB: #{ActiveRecord::Base.connection.current_database}"
      counts = Hash.new(0)
      Listing.includes(:category, images_attachments: :blob).find_each { |l| counts[SeedPhotos.attach!(l)] += 1 }
      broken = ActiveStorage::Attachment.where(record_type: Listing.name, name: "images").includes(:blob)
                                        .count { |a| a.blob.byte_size.to_i.zero? || !a.blob.service.exist?(a.blob.key) }
      puts "listings: #{counts.inspect}; listing photos still missing or empty: #{broken}"
      abort "photos still broken" if broken.positive?
    end
  end
end
