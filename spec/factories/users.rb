FactoryBot.define do
  factory :user do
    firstname { Faker::Name.first_name }
    lastname  { Faker::Name.last_name }
    email     { Faker::Internet.unique.email }
    password  { "password123" }
    password_confirmation { "password123" }
    city      { "Kabul" }
    preferred_language { "ps" }
    status    { :active }

    trait :verified do
      verified { true }
    end
  end
end
