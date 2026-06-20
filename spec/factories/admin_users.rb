FactoryBot.define do
  factory :admin_user do
    name { Faker::Name.name }
    sequence(:email) { |n| "admin#{n}@hatiwal.com" }
    password { "changeme123!" }
  end
end
