FactoryBot.define do
  factory :transaction do
    # `seller` drives `listing` (not the other way around) so that overriding
    # just `seller:` on the factory still produces a listing owned by that
    # seller — required by the `seller_matches_listing_owner` validation.
    # Everything uses explicit `create` (not `association`) so records are
    # always persisted with real ids regardless of the parent's build
    # strategy — validations and the after(:build) hook below both need real
    # foreign keys to compare, even under `FactoryBot.build(:transaction)`.
    seller  { create(:user) }
    listing { create(:listing, :active, user: seller) }
    buyer   { create(:user) }

    final_price { listing.price }
    currency    { listing.currency }
    status      { :reserved }

    # The buyer must be a conversation participant on the listing (model
    # validation) — auto-create one unless the caller already set one up.
    after(:build) do |txn|
      unless txn.buyer_id == txn.seller_id || Conversation.exists?(listing_id: txn.listing_id, seller_id: txn.seller_id, buyer_id: txn.buyer_id)
        create(:conversation, listing: txn.listing, seller: txn.seller, buyer: txn.buyer)
      end
    end

    trait :sold do
      status       { :sold }
      completed_at { Time.current }
    end
  end
end
