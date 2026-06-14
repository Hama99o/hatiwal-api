FactoryBot.define do
  factory :saved_search do
    user
    category { nil }
    location { Faker::Address.city }
    price_min { nil }
    price_max { nil }
    latitude { nil }
    longitude { nil }
    radius { nil }
  end
end
