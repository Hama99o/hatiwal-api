FactoryBot.define do
  factory :review do
    # A sold sale with an auto-created buyer<->seller conversation (see the
    # transaction factory). Default: the SELLER reviewing the BUYER.
    sale { create(:transaction, :sold) }
    reviewer { sale.seller }
    reviewee { sale.buyer }
    role     { :of_buyer }
    rating   { 5 }
    comment  { "Great to deal with." }

    # The BUYER reviewing the SELLER.
    trait :of_seller do
      reviewer { sale.buyer }
      reviewee { sale.seller }
      role     { :of_seller }
    end

    # Already revealed (as if the counterparty also reviewed / window elapsed).
    trait :visible do
      visible     { true }
      revealed_at { Time.current }
    end
  end
end
