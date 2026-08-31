FactoryBot.define do
  factory :message do
    association :conversation
    association :user

    body { Faker::Lorem.sentence }
    kind { :text }

    trait :deleted do
      deleted_at { Time.current }
    end

    # SF-B11 — an offer. The body carries the pipe encoding the serializer parses
    # `offer_amount`/`offer_currency` out of ("amount|currency|listedPrice").
    #
    # `offer_quantity` is deliberately LEFT NIL here: nil means "the sender said
    # nothing about how many", which is what every offer in the app is until a
    # client starts sending one, and every spec that does not care about quantity
    # must keep exercising exactly that row. Set it explicitly where it matters.
    trait :offer do
      kind { :offer }
      body { "8000|AFN|10000" }
    end

    trait :offer_counter do
      kind { :offer_counter }
      body { "9000|AFN|10000" }
    end
  end
end
