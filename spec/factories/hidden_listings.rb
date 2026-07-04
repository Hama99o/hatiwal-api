FactoryBot.define do
  factory :hidden_listing do
    association :user
    association :listing
  end
end
