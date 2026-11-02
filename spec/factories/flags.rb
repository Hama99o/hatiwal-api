FactoryBot.define do
  factory :flag do
    association :flaggable, factory: %i[listing active]
    source { :term }
    status { :open }
    category { :firearms }
    matched_term { "pistol" }

    trait :from_report do
      source { :report }
      category { nil }
      matched_term { nil }
    end

    trait :on_shop do
      association :flaggable, factory: :shop
    end

    trait :dismissed do status { :dismissed } end
    trait :actioned do status { :actioned } end
  end
end
