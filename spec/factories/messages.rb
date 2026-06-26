FactoryBot.define do
  factory :message do
    association :conversation
    association :user

    body { Faker::Lorem.sentence }
    kind { :text }

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
