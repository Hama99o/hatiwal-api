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

    # A confirmed email: needed to open a shop or apply for Verified (email gate, 1.1.6).
    trait :confirmed do
      confirmed_at { Time.current }
    end

    # VER-1: may apply for the badge (confirmed email + profile photo + full name).
    trait :verification_eligible do
      confirmed_at { Time.current }
      after(:build) do |user|
        user.avatar.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open,
                           filename: "avatar.jpg", content_type: "image/jpeg")
      end
    end
  end
end
