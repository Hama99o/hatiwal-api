FactoryBot.define do
  factory :conversation do
    association :listing
    association :buyer,  factory: :user
    association :seller, factory: :user
    status { :open }

    after(:build) do |conv|
      conv.seller = conv.listing.user
    end
  end
end
