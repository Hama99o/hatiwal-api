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

    trait :with_image do
      after(:create) do |listing|
        listing.images.attach(
          io:           StringIO.new("fake image data"),
          filename:     "photo.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end
