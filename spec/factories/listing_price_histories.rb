FactoryBot.define do
  factory :listing_price_history do
    association :listing

    old_price  { 5000.00 }
    new_price  { 4000.00 }
    currency   { "AFN" }
    changed_at { 3.days.ago }

    # A recent reduction within the 14-day window.
    trait :recent_drop do
      changed_at { 5.days.ago }
      old_price  { 10_000.00 }
      new_price  { 8_000.00 }
    end

    # An old reduction outside the 14-day window.
    trait :old_drop do
      changed_at { 20.days.ago }
    end

    # A price increase (not a drop).
    trait :increase do
      old_price  { 3000.00 }
      new_price  { 4500.00 }
    end
  end
end
