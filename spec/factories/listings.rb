FactoryBot.define do
  factory :listing do
    association :user
    association :category

    title       { Faker::Commerce.product_name }
    description { Faker::Lorem.paragraph }
    price       { Faker::Commerce.price(range: 100.0..100_000.0).round(2) }
    currency    { "AFN" }
    status      { :draft }
    location    { "Kabul, Afghanistan" }

    trait :active   do status { :active } end
    trait :reserved do status { :reserved } end
    trait :sold     do status { :sold } end
    # Active but past its expiry window — hidden from the buyer feed.
    trait :expired do
      status     { :active }
      expires_at { 1.day.ago }
    end

    trait :with_image do
      after(:create) do |listing|
        # Attach a REAL image (not fake bytes) so Active Storage variant
        # processing (libvips) can resize it — thumbnail_url now serves a
        # resized variant, which cannot process arbitrary non-image data.
        listing.images.attach(
          io:           File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
          filename:     "test_image.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    # VID: a real (2 s, 320x240) MP4 plus a poster frame.
    trait :with_video do
      after(:create) do |listing|
        listing.video.attach(
          io:           File.open(Rails.root.join("spec/fixtures/files/test_video.mp4")),
          filename:     "test_video.mp4",
          content_type: "video/mp4",
          metadata:     { "duration" => 2.0 }
        )
        listing.video_poster.attach(
          io:           File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
          filename:     "poster.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end
