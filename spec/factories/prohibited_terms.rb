FactoryBot.define do
  factory :prohibited_term do
    sequence(:term) { |n| "forbiddenword#{n}" }
    locale { :en }
    category { :drugs }
  end
end
