FactoryBot.define do
  factory :category do
    sequence(:name_en) { |n| "Category #{n}" }
    sequence(:name_ps) { |n| "کټاګورۍ #{n}" }
    sequence(:name_fa) { |n| "دسته #{n}" }
    sequence(:slug)    { |n| "category-#{n}" }
    icon { "📦" }
    position { 1 }
    active { true }
  end
end
