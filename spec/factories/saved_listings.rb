FactoryBot.define do
  factory :saved_listing do
    association :user
    association :listing
  end
end
