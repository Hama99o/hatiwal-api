FactoryBot.define do
  factory :listing_view do
    user
    listing
    last_viewed_at { Time.current }
  end
end
