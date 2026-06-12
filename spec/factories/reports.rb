FactoryBot.define do
  factory :report do
    association :reporter,   factory: :user
    association :reportable, factory: :listing
    reason      { :spam }
    status      { :pending }
    description { "This listing looks suspicious." }

    trait :fraud           do reason { :fraud } end
    trait :inappropriate   do reason { :inappropriate } end
    trait :wrong_category  do reason { :wrong_category } end
    trait :prohibited_item do reason { :prohibited_item } end

    trait :reviewed  do status { :reviewed } end
    trait :resolved  do status { :resolved } end
    trait :dismissed do status { :dismissed } end

    trait :against_user do
      association :reportable, factory: :user
    end
  end
end
