FactoryBot.define do
  factory :message do
    association :conversation
    association :user

    body { Faker::Lorem.sentence }
    kind { :text }
  end
end
