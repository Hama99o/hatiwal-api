FactoryBot.define do
  factory :block do
    association :blocker, factory: :user
    association :blocked, factory: :user
  end
end
