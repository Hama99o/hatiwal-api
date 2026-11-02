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

    # A shop strike (owner, 2026-10-16): belongs to a shop, not a user.
    trait :for_shop do
      user { nil }
      association :shop
      category { :prohibited_item }
      reason { "Prohibited item (firearms): Kalashnikov" }
    end
  end
end
