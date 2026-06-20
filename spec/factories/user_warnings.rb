FactoryBot.define do
  factory :user_warning do
    association :user
    association :admin_user
    category { :spam }
    reason { "Posting spam listings" }
    # expires_at is set by the model's before_validation when left nil.

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :harassment do
      category { :harassment }
      reason { "Harassing other users" }
    end
  end
end
