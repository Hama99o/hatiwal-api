FactoryBot.define do
  factory :price_guide do
    category
    currency { "AFN" }
    sales_count { 7 }
    sellers_count { 4 }
    low { 8_000 }
    high { 11_000 }
    available { true }
    refreshed_at { Time.current }
  end
end
