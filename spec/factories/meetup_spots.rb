FactoryBot.define do
  factory :meetup_spot do
    city_key { "kabul" }
    sequence(:name_en) { |n| "Shopping Centre #{n}" }
    name_fa { "مرکز خرید" }
    name_ps { "د پلورنې مرکز" }
    kind { :mall }
    latitude { 34.53244 }
    longitude { 69.16566 }
    active { true }
    needs_local_check { false }
  end
end
