FactoryBot.define do
  factory :conversation do
    association :listing
    association :buyer,  factory: :user
    association :seller, factory: :user
    status { :open }

    after(:build) do |conv|
      conv.seller = conv.listing.user
      # Like Conversations::StartService: the chat's shop is pinned at start.
      conv.shop_id ||= conv.listing&.shop_id
    end
  end
end
